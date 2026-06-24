use almost_enough::SyncStopper;
use butteraugli::precompute::ButteraugliReference;
use butteraugli::{
    butteraugli_linear_strip_with_stop, butteraugli_linear_with_stop, butteraugli_strip_with_stop,
    butteraugli_with_stop, ButteraugliError, ButteraugliParams, ButteraugliResult, ImgVec, RGB,
    RGB8,
};
use enough::{Stop, Unstoppable};
use rustler::types::atom;
use rustler::{Atom, Binary, Encoder, Env, OwnedBinary, ResourceArc, Term};

/// Interior rows per strip at the sRGB one-shot strip path. 256 bounds peak
/// working memory and gives tight cancellation latency; must be >= MIN_STRIP_HEIGHT (8).
const STRIP_HEIGHT: u32 = 256;

#[derive(rustler::NifTaggedEnum)]
enum CompareError {
    Cancelled,
    Failed(String),
}

fn to_compare_error(e: ButteraugliError) -> CompareError {
    match e {
        ButteraugliError::Cancelled(_) => CompareError::Cancelled,
        other => CompareError::Failed(other.to_string()),
    }
}

mod atoms {
    rustler::atoms! {
        ok,
        rgb888,
        linear_rgb,
    }
}

#[rustler::nif]
fn nif_loaded() -> bool {
    true
}

struct StopResource {
    stopper: SyncStopper,
}

#[rustler::resource_impl]
impl rustler::Resource for StopResource {}

/// Create a fresh, live cancellation token. Regular (non-dirty) NIF.
#[rustler::nif]
fn token_new() -> ResourceArc<StopResource> {
    ResourceArc::new(StopResource {
        stopper: SyncStopper::new(),
    })
}

/// Trip a cancellation token. Regular NIF — runs instantly on a normal
/// scheduler, so it can cancel a token while a dirty `compare` blocks.
#[rustler::nif]
fn token_cancel(token: ResourceArc<StopResource>) -> Atom {
    token.stopper.cancel();
    atoms::ok()
}

enum Format {
    Rgb888,
    LinearRgb,
}

impl Format {
    fn from_atom(a: Atom) -> Result<Self, String> {
        if a == atoms::rgb888() {
            Ok(Format::Rgb888)
        } else if a == atoms::linear_rgb() {
            Ok(Format::LinearRgb)
        } else {
            Err("unknown format".to_string())
        }
    }
}

// Owned pixel buffers. BEAM (sub-)binaries are not guaranteed 2-/4-byte aligned,
// so copy into owned, aligned buffers via from_ne_bytes rather than casting.
fn rgb888_img(b: &[u8], w: usize, h: usize) -> ImgVec<RGB8> {
    let px: Vec<RGB8> = b
        .chunks_exact(3)
        .map(|c| RGB8::new(c[0], c[1], c[2]))
        .collect();
    ImgVec::new(px, w, h)
}

fn linear_img(b: &[u8], w: usize, h: usize) -> ImgVec<RGB<f32>> {
    let px: Vec<RGB<f32>> = b
        .chunks_exact(12)
        .map(|c| {
            RGB::new(
                f32::from_ne_bytes([c[0], c[1], c[2], c[3]]),
                f32::from_ne_bytes([c[4], c[5], c[6], c[7]]),
                f32::from_ne_bytes([c[8], c[9], c[10], c[11]]),
            )
        })
        .collect();
    ImgVec::new(px, w, h)
}

fn to_f32_vec(b: &[u8]) -> Vec<f32> {
    b.chunks_exact(4)
        .map(|c| f32::from_ne_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

fn build_params(
    intensity_target: Option<f64>,
    hf_asymmetry: Option<f64>,
    compute_diffmap: bool,
) -> ButteraugliParams {
    let mut p = ButteraugliParams::new();
    if let Some(it) = intensity_target {
        p = p.with_intensity_target(it as f32);
    }
    if let Some(hf) = hf_asymmetry {
        p = p.with_hf_asymmetry(hf as f32);
    }
    p.with_compute_diffmap(compute_diffmap)
}

// One-shot scoring. sub-8px inputs take the non-strip path (reflect-padded to
// 8x8, single cancellation check at entry); larger inputs of either format take
// the strip path (bounded memory + per-strip cancellation).
fn score_oneshot(
    fmt: &Format,
    r: &[u8],
    d: &[u8],
    w: usize,
    h: usize,
    params: &ButteraugliParams,
    stop: &dyn Stop,
) -> Result<ButteraugliResult, CompareError> {
    let result = match fmt {
        Format::Rgb888 => {
            let (a, b) = (rgb888_img(r, w, h), rgb888_img(d, w, h));
            if w < 8 || h < 8 {
                butteraugli_with_stop(a.as_ref(), b.as_ref(), params, stop)
            } else {
                butteraugli_strip_with_stop(a.as_ref(), b.as_ref(), params, STRIP_HEIGHT, stop)
            }
        }
        Format::LinearRgb => {
            let (a, b) = (linear_img(r, w, h), linear_img(d, w, h));
            if w < 8 || h < 8 {
                butteraugli_linear_with_stop(a.as_ref(), b.as_ref(), params, stop)
            } else {
                butteraugli_linear_strip_with_stop(
                    a.as_ref(),
                    b.as_ref(),
                    params,
                    STRIP_HEIGHT,
                    stop,
                )
            }
        }
    };
    result.map_err(to_compare_error)
}

// Encode a ButteraugliResult as {score, pnorm_3, diffmap}. The diffmap is a
// packed native-endian f32 binary (row-major, w*h values) when present, else nil.
fn encode_result<'a>(
    env: Env<'a>,
    r: ButteraugliResult,
) -> Result<(f64, f64, Term<'a>), CompareError> {
    let diff = match r.diffmap {
        Some(map) => {
            let (buf, _w, _h) = map.into_contiguous_buf();
            let bytes: &[u8] = bytemuck::cast_slice(&buf);
            let mut bin = OwnedBinary::new(bytes.len())
                .ok_or_else(|| CompareError::Failed("diffmap binary allocation failed".into()))?;
            bin.as_mut_slice().copy_from_slice(bytes);
            bin.release(env).encode(env)
        }
        None => atom::nil().encode(env),
    };
    Ok((r.score, r.pnorm_3, diff))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn compare<'a>(
    env: Env<'a>,
    reference: Binary,
    distorted: Binary,
    width: usize,
    height: usize,
    format: Atom,
    intensity_target: Option<f64>,
    hf_asymmetry: Option<f64>,
    compute_diffmap: bool,
    cancel: Option<ResourceArc<StopResource>>,
) -> Result<(f64, f64, Term<'a>), CompareError> {
    let fmt = Format::from_atom(format).map_err(CompareError::Failed)?;
    let params = build_params(intensity_target, hf_asymmetry, compute_diffmap);
    let unstoppable = Unstoppable;
    let stop: &dyn Stop = match &cancel {
        Some(res) => &res.stopper,
        None => &unstoppable,
    };
    let result = score_oneshot(
        &fmt,
        reference.as_slice(),
        distorted.as_slice(),
        width,
        height,
        &params,
        stop,
    )?;
    encode_result(env, result)
}

struct ReferenceResource {
    inner: ButteraugliReference,
    format: Format,
}

#[rustler::resource_impl]
impl rustler::Resource for ReferenceResource {}

#[rustler::nif(schedule = "DirtyCpu")]
fn reference_new(
    source: Binary,
    width: usize,
    height: usize,
    format: Atom,
    intensity_target: Option<f64>,
    hf_asymmetry: Option<f64>,
    compute_diffmap: bool,
) -> Result<ResourceArc<ReferenceResource>, String> {
    let fmt = Format::from_atom(format)?;
    let params = build_params(intensity_target, hf_asymmetry, compute_diffmap);
    let s = source.as_slice();
    let inner = match fmt {
        Format::Rgb888 => ButteraugliReference::new(s, width, height, params),
        Format::LinearRgb => {
            ButteraugliReference::new_linear(&to_f32_vec(s), width, height, params)
        }
    }
    .map_err(|e| e.to_string())?;
    Ok(ResourceArc::new(ReferenceResource { inner, format: fmt }))
}

// `use_strips` selects the strip-bounded walker (bounded peak memory + per-strip
// mid-flight cancellation) over the default warm path (reuses the precomputed
// reference pyramid — ~2x faster — but checks cancellation only at entry). The
// strip walker recomputes the reference side per strip, discarding the
// precompute. References are always >= 8x8 (built via reference_new), so the
// strip walker's minimum-size requirement always holds here.
#[rustler::nif(schedule = "DirtyCpu")]
fn reference_compare<'a>(
    env: Env<'a>,
    reference: ResourceArc<ReferenceResource>,
    distorted: Binary,
    cancel: Option<ResourceArc<StopResource>>,
    use_strips: bool,
) -> Result<(f64, f64, Term<'a>), CompareError> {
    let unstoppable = Unstoppable;
    let stop: &dyn Stop = match &cancel {
        Some(res) => &res.stopper,
        None => &unstoppable,
    };
    let d = distorted.as_slice();
    let result = match (&reference.format, use_strips) {
        (Format::Rgb888, false) => reference.inner.compare_with_stop(d, stop),
        (Format::Rgb888, true) => reference
            .inner
            .compare_strip_with_stop(d, STRIP_HEIGHT, stop),
        (Format::LinearRgb, false) => reference
            .inner
            .compare_linear_with_stop(&to_f32_vec(d), stop),
        (Format::LinearRgb, true) => {
            reference
                .inner
                .compare_linear_strip_with_stop(&to_f32_vec(d), STRIP_HEIGHT, stop)
        }
    }
    .map_err(to_compare_error)?;
    encode_result(env, result)
}

rustler::init!("Elixir.Butteraugli.Native");
