# whisrs (https://github.com/y0sif/whisrs): local voice-to-text dictation,
# built with whisper.cpp's Vulkan backend so transcription runs on the iGPU.
#
# Upstream's flake package is CPU-only, and on top of that Nix sets
# SOURCE_DATE_EPOCH, which makes ggml default GGML_NATIVE to OFF: the bundled
# whisper.cpp then builds without AVX at all. Measured on this machine, 8 s of
# speech took ~25 s on that build vs ~0.7 s with Vulkan on the Arc iGPU.
#
# The daemon is started by hand (`whisrsd`) or via upstream's user unit
# (`systemctl --user enable --now whisrs.service`); it is not enabled here.
{ pkgs, inputs, ... }:

let
  whisrs = inputs.whisrs.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    cargoBuildFeatures = "vulkan";
    cargoCheckFeatures = "vulkan";
    # The test suite adds a second full build of whisper.cpp for no benefit here.
    doCheck = false;

    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.shaderc pkgs.makeWrapper ];
    buildInputs = old.buildInputs ++ [ pkgs.vulkan-headers pkgs.vulkan-loader ];

    # whisper-rs-sys forwards GGML_* env vars to CMake. These match this host's
    # Meteor Lake CPU; ThinkPadT580 (no AVX-VNNI) must not import this module.
    env = (old.env or { }) // {
      GGML_AVX = "ON";
      GGML_AVX2 = "ON";
      GGML_AVX_VNNI = "ON";
      GGML_FMA = "ON";
      GGML_F16C = "ON";
      GGML_BMI2 = "ON";
    };

    # ggml-vulkan prefers a dedicated GPU, so with the RTX eGPU attached the
    # daemon would grab it and hold it open, blocking a live detach
    # (modules/egpu.nix). Expose only the Intel ICD to keep it on the iGPU.
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/whisrsd \
        --set VK_DRIVER_FILES /run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json
    '';
  });
in
{
  environment.systemPackages = [ whisrs ];

  # /dev/uinput access (input group + uaccess) for keystroke injection.
  services.udev.packages = [ whisrs ];
}
