// Original code from https://github.com/koeqaife/hyprland-material-you
// Original code license: GPLv3
// Translated to Js from Cython with an LLM and reviewed
// Converted to ES5 for QML V4 engine compatibility

function min3(a, b, c) {
    return a < b && a < c ? a : b < c ? b : c;
}

function max3(a, b, c) {
    return a > b && a > c ? a : b > c ? b : c;
}

function min2(a, b) {
    return a < b ? a : b;
}

function max2(a, b) {
    return a > b ? a : b;
}

function levenshteinDistance(s1, s2) {
    var len1 = s1.length;
    var len2 = s2.length;

    if (len1 === 0) return len2;
    if (len2 === 0) return len1;

    // Swap if needed (ES5 style)
    if (len2 > len1) {
        var temp = s1;
        s1 = s2;
        s2 = temp;
        var tempLen = len1;
        len1 = len2;
        len2 = tempLen;
    }

    var prev = new Array(len2 + 1);
    var curr = new Array(len2 + 1);

    for (var j = 0; j <= len2; j++) {
        prev[j] = j;
    }

    for (var i = 1; i <= len1; i++) {
        curr[0] = i;
        for (var k = 1; k <= len2; k++) {
            var cost = s1[i - 1] === s2[k - 1] ? 0 : 1;
            curr[k] = min3(prev[k] + 1, curr[k - 1] + 1, prev[k - 1] + cost);
        }
        // Swap prev and curr (ES5 style)
        var swapTemp = prev;
        prev = curr;
        curr = swapTemp;
    }

    return prev[len2];
}

function partialRatio(shortS, longS) {
    var lenS = shortS.length;
    var lenL = longS.length;
    var best = 0.0;

    if (lenS === 0) return 1.0;

    for (var i = 0; i <= lenL - lenS; i++) {
        var sub = longS.slice(i, i + lenS);
        var dist = levenshteinDistance(shortS, sub);
        var score = 1.0 - (dist / lenS);
        if (score > best) best = score;
    }

    return best;
}

function computeScore(s1, s2) {
    if (s1 === s2) return 1.0;

    var dist = levenshteinDistance(s1, s2);
    var maxLen = max2(s1.length, s2.length);
    if (maxLen === 0) return 1.0;

    var full = 1.0 - (dist / maxLen);
    var part = s1.length < s2.length ? partialRatio(s1, s2) : partialRatio(s2, s1);

    var score = 0.85 * full + 0.15 * part;

    if (s1 && s2 && s1[0] !== s2[0]) {
        score -= 0.05;
    }

    var lenDiff = Math.abs(s1.length - s2.length);
    if (lenDiff >= 3) {
        score -= 0.05 * lenDiff / maxLen;
    }

    var commonPrefixLen = 0;
    var minLen = min2(s1.length, s2.length);
    for (var i = 0; i < minLen; i++) {
        if (s1[i] === s2[i]) {
            commonPrefixLen++;
        } else {
            break;
        }
    }
    score += 0.02 * commonPrefixLen;

    if (s1.includes(s2) || s2.includes(s1)) {
        score += 0.06;
    }

    return Math.max(0.0, Math.min(1.0, score));
}

function computeTextMatchScore(s1, s2) {
    if (s1 === s2) return 1.0;

    var dist = levenshteinDistance(s1, s2);
    var maxLen = max2(s1.length, s2.length);
    if (maxLen === 0) return 1.0;

    var full = 1.0 - (dist / maxLen);
    var part = s1.length < s2.length ? partialRatio(s1, s2) : partialRatio(s2, s1);

    var score = 0.4 * full + 0.6 * part;

    var lenDiff = Math.abs(s1.length - s2.length);
    if (lenDiff >= 10) {
        score -= 0.02 * lenDiff / maxLen;
    }

    var commonPrefixLen = 0;
    var minLen = min2(s1.length, s2.length);
    for (var i = 0; i < minLen; i++) {
        if (s1[i] === s2[i]) {
            commonPrefixLen++;
        } else {
            break;
        }
    }
    score += 0.01 * commonPrefixLen;

    if (s1.includes(s2) || s2.includes(s1)) {
        score += 0.2;
    }

    return Math.max(0.0, Math.min(1.0, score));
}
