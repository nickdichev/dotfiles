{
  fetchFromGitHub,
  minizip,
  qtshadertools,
  telegram-desktop,
}:

telegram-desktop.override {
  unwrapped = (telegram-desktop.unwrapped.override { minizip-ng = minizip; }).overrideAttrs (
    finalAttrs: _previousAttrs: {
      version = "6.9.3";

      src = fetchFromGitHub {
        owner = "telegramdesktop";
        repo = "tdesktop";
        rev = "v${finalAttrs.version}";
        fetchSubmodules = true;
        hash = "sha256-QCGtESg+38lHWCFcsevHdc0kQ7LKJQmJjUJWszphah8=";
      };

      nativeBuildInputs = _previousAttrs.nativeBuildInputs ++ [
        qtshadertools
      ];
    }
  );
}
