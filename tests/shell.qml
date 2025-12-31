//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "./modules/common"
import "./services"
import QtQuick
import Quickshell

/**
 * Test runner for booru providers.
 * Run with: qs -c tests
 */
ShellRoot {
    id: root

    Component.onCompleted: {
        ConfigLoader.loadConfig()
        testRunner.start()
    }

    ProviderTests {
        id: testRunner
        onTestsCompleted: (passed, failed) => {
            console.log("")
            console.log("========================================")
            var summary = "Image Tests: " + passed + " passed, " + failed + " failed"
            if (testRunner.skippedCount > 0) {
                summary += ", " + testRunner.skippedCount + " skipped"
            }
            console.log(summary)
            console.log("Autocomplete: " + testRunner.autocompletePassedCount + " passed, " +
                        testRunner.autocompleteFailedCount + " failed")
            console.log("========================================")
            Qt.quit()
        }
    }
}
