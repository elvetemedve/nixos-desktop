# QLC+ 5.3.0, based on the pending nixpkgs update
# (https://github.com/NixOS/nixpkgs/pull/553412) -- the pinned nixpkgs still
# has 5.0.0. Drop everything here but `patches` once that PR lands, and turn
# this into an overrideAttrs on pkgs.qlcplus.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  udevCheckHook,
  udev,
  qt6,
  alsa-lib,
  ola,
  libftdi1,
  libusb1,
  libsndfile,
  fftw,
}:

stdenv.mkDerivation rec {
  pname = "qlcplus";
  version = "5.3.0";

  src = fetchFromGitHub {
    owner = "mcallegari";
    repo = "qlcplus";
    rev = "QLC+_${version}";
    hash = "sha256-55Jy4t60Lc6YOGko6fW/pUjS5uAiNhVDn4bm8LBWkzI=";
  };

  # OS2L feedback, so VirtualDJ can light its os2l_button pads, and a fix
  # for Enttec Pro clones such as the Eurolite USB-DMX512 Pro; see
  # ./default.nix.
  patches = [
    ./os2l-feedback.patch
    ./os2l-bpm.patch
    ./dmxusb-pro-serial-close.patch
  ];

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    udevCheckHook
    qt6.wrapQtAppsHook
  ];
  buildInputs = [
    udev
    alsa-lib
    ola
    libftdi1
    libusb1
    libsndfile
    fftw
  ]
  ++ (with qt6; [
    qtbase
    qtdeclarative
    qtmultimedia
    qtserialport
    qtsvg
    qttools
    qtwebsockets
    qt3d
  ]);

  postPatch = ''
    patchShebangs .

    # Fix build failure caused by newer compilers/Qt turning on additional
    # warnings (e.g. -Wunused-result for [[nodiscard]] QFile::open) by
    # removing the blanket -Werror.
    substituteInPlace variables.cmake --replace-fail 'set(CMAKE_CXX_FLAGS "''${CMAKE_CXX_FLAGS} -Werror")' ""

    # On Linux, QLC+'s build system hardcodes all of its installation
    # directories (binaries, libraries, data files, ...) to be relative to
    # "/usr", following the same "install root" convention used by its
    # Debian packaging (see INSTALL_ROOT below). Drop that hardcoded "/usr"
    # prefix so everything installs directly under $out in the conventional
    # FHS-style layout instead of $out/usr.
    substituteInPlace variables.cmake --replace-fail 'set(INSTALLROOT "/usr")' 'set(INSTALLROOT "")'

    # Since 5.3.0, QLC+ discards any CMAKE_INSTALL_LIBDIR it is given and
    # recomputes it with GNUInstallDirs, which picks "lib64" here. The
    # binary's RUNPATH is then shrunk before fixup moves lib64 into lib, so
    # it loses $out/lib and cannot find libqlcplusengine5.so. Install the
    # libraries straight into lib instead.
    substituteInPlace variables.cmake --replace-fail 'set(LIBSDIR "''${CMAKE_INSTALL_LIBDIR}")' 'set(LIBSDIR "lib")'
  '';

  cmakeFlags = [
    # QLC+ 5's QML-based UI, as opposed to the legacy Qt Widgets UI.
    (lib.cmakeBool "qmlui" true)
    # See the INSTALLROOT patch in postPatch above: this is prepended to it
    # (and to a few paths that don't use INSTALLROOT, like the udev rules
    # directory) to form the actual installation prefix.
    (lib.cmakeFeature "INSTALL_ROOT" (placeholder "out"))
  ];

  enableParallelBuilding = true;

  doInstallCheck = true;

  postInstall = ''
    ln -sf $out/lib/*/libqlcplus* $out/lib
  '';

  meta = {
    description = "Free and cross-platform software to control DMX or analog lighting systems like moving heads, dimmers, scanners etc";
    maintainers = with lib.maintainers; [
      giomf
    ];
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
    homepage = "https://www.qlcplus.org/";
  };
}
