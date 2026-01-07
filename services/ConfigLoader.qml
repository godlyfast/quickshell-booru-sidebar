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
    signal configLoadFailed(string error)

    // Write queue to prevent concurrent file writes
    property bool writeInProgress: false
    property string pendingWrite: ""

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
            root.configLoadFailed(String(e))
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
            }
            onStarted: {
                Logger.debug("ConfigLoader", "Writer process started");
                // Always write and close stdin, even for empty content
                write(jsonContent);
                Logger.debug("ConfigLoader", `Wrote ${jsonContent.length} bytes, closing stdin`);
                stdinEnabled = false;  // Close stdin to signal EOF
            }
            onExited: (code) => {
                root.writeInProgress = false
                if (code === 0) {
                    Logger.info("ConfigLoader", `Config saved successfully to: ${targetPath}`);
                } else {
                    Logger.error("ConfigLoader", `Failed to save config, exit code: ${code}`);
                }
                // Check for pending write and process it
                if (root.pendingWrite.length > 0) {
                    const nextContent = root.pendingWrite
                    root.pendingWrite = ""
                    root.startWrite(nextContent)
                }
                this.destroy();
            }
        }
    }

    // Internal function to start a write operation
    function startWrite(jsonContent) {
        root.writeInProgress = true
        const writer = configWriterComponent.createObject(root, {
            jsonContent: jsonContent,
            targetPath: root.filePath,
            running: true
        });
        if (!writer) {
            Logger.error("ConfigLoader", "Failed to create writer process");
            root.writeInProgress = false
        }
    }

    function saveConfig() {
        const plainConfig = ObjectUtils.toPlainObject(ConfigOptions);
        const jsonContent = JSON.stringify(plainConfig, null, 2);
        Logger.debug("ConfigLoader", `saveConfig called, path: ${root.filePath}`);

        // Queue write if one is already in progress
        if (root.writeInProgress) {
            Logger.debug("ConfigLoader", "Write in progress, queueing...");
            root.pendingWrite = jsonContent
            return
        }

        root.startWrite(jsonContent)
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