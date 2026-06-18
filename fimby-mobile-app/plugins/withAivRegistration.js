const { withDangerousMod } = require("expo/config-plugins");
const fs = require("fs");
const path = require("path");

/**
 * Copies aiv-registration.properties into the Android app's native assets
 * folder so it is bundled into the built APK/AAB. Google Play uses this file
 * to verify ownership of the app's signing key (Android developer verification).
 */
const withAivRegistration = (config) => {
  return withDangerousMod(config, [
    "android",
    async (config) => {
      const projectRoot = config.modRequest.projectRoot;
      const source = path.join(projectRoot, "aiv-registration.properties");
      const assetsDir = path.join(
        config.modRequest.platformProjectRoot,
        "app",
        "src",
        "main",
        "assets"
      );
      const destination = path.join(assetsDir, "aiv-registration.properties");

      if (!fs.existsSync(source)) {
        throw new Error(
          `withAivRegistration: expected source file at ${source} but it was not found.`
        );
      }

      fs.mkdirSync(assetsDir, { recursive: true });
      fs.copyFileSync(source, destination);

      return config;
    },
  ]);
};

module.exports = withAivRegistration;
