/**
 * Formats a string according to the args that are passed in
 * @param { string } str
 * @param  {...any} args
 * @returns
 */
function format(str) {
    var args = Array.prototype.slice.call(arguments, 1);
    return str.replace(/{(\d+)}/g, function(match, index) {
        return typeof args[index] !== 'undefined' ? args[index] : match;
    });
}

/**
 * Returns the domain of the passed in url or null
 * @param { string } url
 * @returns { string| null }
 */
function getDomain(url) {
    var match = url.match(/^(?:https?:\/\/)?(?:www\.)?([^\/]+)/);
    return match ? match[1] : null;
}

/**
 * Returns the base url of the passed in url or null
 * @param { string } url
 * @returns { string | null }
 */
function getBaseUrl(url) {
    var match = url.match(/^(https?:\/\/[^\/]+)(\/.*)?$/);
    return match ? match[1] : null;
}

/**
 * Escapes single quotes in shell commands
 * @param { string } str
 * @returns { string }
 */
function shellSingleQuoteEscape(str) {
    //  escape single quotes
    return String(str)
        // .replace(/\\/g, '\\\\')
        .replace(/'/g, "'\\''");
}

function escapeHtml(str) {
    if (typeof str !== 'string') return str;
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
