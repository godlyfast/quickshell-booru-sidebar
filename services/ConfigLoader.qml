pragma Singleton
pragma ComponentBehavior: Bound

import "../modules/common"
import "../modules/common/functions/file_utils.js" as FileUtils
import "../modules/common/functions/string_utils.js" as StringUtils
import "../modules/common/functions/object_utils.js" as ObjectUtils
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Qt.labs.platform

/**
 * Loads and manages the shell configuration file.
 * The config file is by default at XDG_CONFIG_HOME/quickshell/config.json.
 * Automatically reloaded when the file changes, but does not provide a way to save changes.
 */
Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property bool firstLoad: true

    signal configLoaded()

    function loadConfig() {
        configFileView.reload()
    }

    function applyConfig(fileContent) {
        try {
            const json = JSON.parse(fileContent);

            // Extract font configuration if it exists
            let fontConfig = null;
            let configForOptions = {};
            
            // Copy all properties except font to configForOptions
            for (let key in json) {
                if (key !== "font") {
                    configForOptions[key] = json[key];
                } else {
                    fontConfig = json[key];
                }
            }

            // Apply the non-font configuration to ConfigOptions
            ObjectUtils.applyToQtObject(ConfigOptions, configForOptions);
            
            // Apply font configuration to Appearance if it exists
            if (fontConfig && typeof Appearance !== 'undefined') {
                if (fontConfig.family && Appearance.font && Appearance.font.family) {
                    ObjectUtils.applyToQtObject(Appearance.font.family, fontConfig.family);
                }
                if (fontConfig.pixelSize && Appearance.font && Appearance.font.pixelSize) {
                    ObjectUtils.applyToQtObject(Appearance.font.pixelSize, fontConfig.pixelSize);
                }
            }

            if (root.firstLoad) {
                root.firstLoad = false;
            } else {
                Hyprland.dispatch(`exec notify-send "${qsTr("Shell configuration reloaded")}" "${root.filePath}"`)
            }

            // Notify listeners that config is loaded
            root.configLoaded()
        } catch (e) {
            Logger.error("ConfigLoader", `Error reading file: ${e}`);
            Hyprland.dispatch(`exec notify-send "${qsTr("Shell configuration failed to load")}" "${root.filePath}"`)
            return;
        }
    }

    function setLiveConfigValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let targetObject = ConfigOptions;
        
        // Check if this is a font-related configuration
        if (keys[0] === "font") {
            targetObject = Appearance;
        }
        
        let obj = targetObject;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        Logger.debug("ConfigLoader", `Setting live config value: ${nestedKey} = ${convertedValue}`);
        obj[keys[keys.length - 1]] = convertedValue;
    }

    property Component configWriterComponent: Component {
        Process {
            property string jsonContent: ""
            property string targetPath: ""
            command: ["dd", "status=none", "of=" + targetPath]
            stdinEnabled: true
            Component.onCompleted: {
                Logger.debug("ConfigLoader", `Writer process created, target: ${targetPath}`);
                Logger.debug("ConfigLoader", `Command: ${JSON.stringify(command)}`);
            }
            onStarted: {
                Logger.debug("ConfigLoader", "Writer process started");
                if (jsonContent.length > 0) {
                    write(jsonContent);
                    Logger.debug("ConfigLoader", `Wrote ${jsonContent.length} bytes, closing stdin`);
                    stdinEnabled = false;  // Close stdin to signal EOF
                }
            }
            onExited: (code) => {
                if (code === 0) {
                    Logger.info("ConfigLoader", `Config saved successfully to: ${targetPath}`);
                } else {
                    Logger.error("ConfigLoader", `Failed to save config, exit code: ${code}`);
                }
                this.destroy();
            }
        }
    }

    function saveConfig() {
        const plainConfig = ObjectUtils.toPlainObject(ConfigOptions);
        const jsonContent = JSON.stringify(plainConfig, null, 2);
        Logger.debug("ConfigLoader", `saveConfig called, path: ${root.filePath}`);
        Logger.debug("ConfigLoader", `JSON content length: ${jsonContent.length}`);
        // Create fresh Process for each save to avoid stdin closure issues
        const writer = configWriterComponent.createObject(root, {
            jsonContent: jsonContent,
            targetPath: root.filePath,
            running: true
        });
        if (!writer) {
            Logger.error("ConfigLoader", "Failed to create writer process");
        }
    }

    Timer {
        id: delayedFileRead
        interval: ConfigOptions.hacks.arbitraryRaceConditionDelay
        repeat: false
        running: false
        onTriggered: {
            root.applyConfig(configFileView.text())
        }
    }

	FileView { 
        id: configFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            Logger.info("ConfigLoader", "File changed, reloading...")
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = configFileView.text()
            root.applyConfig(fileContent)
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                Logger.info("ConfigLoader", "File not found, creating new file.")
                root.saveConfig()
                Hyprland.dispatch(`exec notify-send "${qsTr("Shell configuration created")}" "${root.filePath}"`)
            } else {
                Hyprland.dispatch(`exec notify-send "${qsTr("Shell configuration failed to load")}" "${root.filePath}"`)
            }
        }
    }
}