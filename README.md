# jellyfin-rusticl

The `jellyfin/jellyfin` image (arm64) with Mesa built from main and three local fixes (`fixes.patch`), so Jellyfin can tone map HDR video on the Mali G610 GPU of the RK3588.

## Why it exists

Jellyfin converts HDR to SDR with ffmpeg's `tonemap_opencl` filter, which needs OpenCL on the GPU. The stock image only ships Arm's proprietary OpenCL (`libMaliOpenCL`), and that requires Rockchip's vendor GPU driver (`mali_kbase`). On mainline Linux the GPU runs on `panthor`, where the proprietary OpenCL can't work.

Mesa's own OpenCL, rusticl, does work on `panthor`. On the RKMPP path, ffmpeg passes each decoded frame to OpenCL without copying it (`hwmap`), and that needs the `cl_arm_import_memory` extension. Rusticl got it on Mesa main in November 2026 (commit `6eb0d201`), so the image builds Mesa from a pinned main commit.

## Why zink and not panfrost

Rusticl can run on two Mesa drivers for this GPU.

- `panfrost`, the native Mali driver, doesn't offer `cl_arm_import_memory`: rusticl only exposes it when the driver declares memory sharing, and panfrost doesn't. It also can't present imported memory as a 2D image, which the tone mapping filter needs. ffmpeg stops with "Platform rusticl does not support the cl_arm_import_memory extension".
- zink runs OpenCL on top of Vulkan, here panvk (Mesa's Vulkan driver for Mali). It offers both, so the image sets `RUSTICL_ENABLE=zink`.

## What fixes.patch changes

Three changes to how frames are imported:

- Rusticl closed the dma-buf fd passed to `clImportMemoryARM`, although ffmpeg still owns it. It now imports a duplicate.
- Zink used the colour plane's offset, which rusticl gives in pixels, as a byte offset, so the colour data was read from inside the brightness plane. It now converts pixels to bytes.
- Zink reported its default 256-pixel row alignment for panvk. It now reports Mali's 64 bytes.

With the patch, imported frames are byte-identical to the RGA scaler's output at 1920x1080 (other sizes untested). A 60 s clip of a 4K HDR10 film converts at 3.05x real time to 1080p and at 1.32x to 4K.

The image also copies LLVM 19's clang headers: rusticl compiles the tone mapping kernel when it first runs and fails without `opencl-c-base.h`.

## Known problem

A conversion gets slower the longer it runs. On a 4K HDR film it went from 1.40x real time after 2 minutes to 0.69x after 21 minutes, and dropped below real time after about 8 minutes, when playback starts to stall. Over that time GPU memory stayed flat, while the process's memory and its number of `renderD128` mappings kept growing, and zink's flush thread (`zfq0`) used a full CPU core. The cause isn't known yet. A seek starts a new conversion, which runs fast again.

## Image

`ghcr.io/lywel/jellyfin-rusticl:<jellyfin tag>-mesa-<first 7 chars of the Mesa commit>`, e.g. `12.4-mesa-ef59438`.

`JELLYFIN_TAG` and `MESA_COMMIT` are set at the top of the `Dockerfile`. The Jellyfin base is also pinned by digest there: update it together with the tag.
