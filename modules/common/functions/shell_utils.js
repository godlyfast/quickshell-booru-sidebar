/**
 * Shell command utilities for safe string escaping and command building.
 */

/**
 * Escapes a string for safe embedding in single-quoted shell strings.
 * Uses the pattern: 'foo'bar' -> 'foo'\''bar' (end quote, escaped quote, start quote)
 *
 * @param {string} str - The string to escape
 * @returns {string} - The escaped string safe for shell use
 *
 * @example
 * // In QML:
 * import "functions/shell_utils.js" as ShellUtils
 * command: ["bash", "-c", "curl '" + ShellUtils.shellEscape(url) + "'"]
 */
function shellEscape(str) {
    if (!str) return "";
    return str.replace(/'/g, "'\\''");
}

/**
 * Builds a curl command with proper escaping and default User-Agent.
 *
 * @param {string} url - The URL to fetch
 * @param {string} outputPath - Path to save the downloaded file
 * @param {string} [userAgent] - Optional User-Agent string (default: Mozilla/5.0 BooruSidebar/1.0)
 * @returns {string} - The complete curl command string
 *
 * @example
 * command: ["bash", "-c", ShellUtils.buildCurlCommand(url, "/path/to/file.jpg")]
 */
function buildCurlCommand(url, outputPath, userAgent) {
    var ua = userAgent || "Mozilla/5.0 BooruSidebar/1.0";
    return "curl -fsSL -A '" + shellEscape(ua) + "' '" +
           shellEscape(url) + "' -o '" + shellEscape(outputPath) + "'";
}

/**
 * Builds a mkdir + curl command chain for downloading to a new directory.
 *
 * @param {string} url - The URL to fetch
 * @param {string} dirPath - Directory path to create
 * @param {string} fileName - File name to save as
 * @param {string} [userAgent] - Optional User-Agent string
 * @returns {string} - The complete command string
 */
function buildDownloadCommand(url, dirPath, fileName, userAgent) {
    var escapedDir = shellEscape(dirPath);
    var escapedFile = shellEscape(fileName);
    var escapedUrl = shellEscape(url);
    var ua = userAgent || "Mozilla/5.0 BooruSidebar/1.0";

    return "mkdir -p '" + escapedDir + "' && " +
           "curl -fsSL -A '" + shellEscape(ua) + "' '" + escapedUrl + "' " +
           "-o '" + escapedDir + "/" + escapedFile + "'";
}
