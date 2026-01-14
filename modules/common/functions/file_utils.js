/**
 * Trims the File protocol off the input string
 * @param {string} str
 * @returns {string}
 */
function trimFileProtocol(str) {
    return str.startsWith("file://") ? str.slice(7) : str;
}

/**
 * Constructs a file:// URL from a local path.
 * Qt's Image component handles raw spaces and special characters in file:// URLs.
 * @param {string} path - Local file path
 * @returns {string} - file:// URL
 */
function toFileUrl(path) {
    if (!path) return "";
    return "file://" + path;
}

