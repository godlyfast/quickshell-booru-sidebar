function toPlainObject(qtObj) {
    if (qtObj === null || typeof qtObj !== "object") return qtObj;

    // Handle arrays
    if (Array.isArray(qtObj)) {
        return qtObj.map(toPlainObject);
    }

    var result = {};
    for (var key in qtObj) {
        if (
            typeof qtObj[key] !== "function" &&
            !key.startsWith("objectName") &&
            !key.startsWith("children") &&
            !key.startsWith("object") &&
            !key.startsWith("parent") &&
            !key.startsWith("metaObject") &&
            !key.startsWith("destroyed") &&
            !key.startsWith("reloadableId")
        ) {
            result[key] = toPlainObject(qtObj[key]);
        }
    }
    return result;
}

function applyToQtObject(qtObj, jsonObj) {
    if (!qtObj || typeof jsonObj !== "object" || jsonObj === null) return;

    for (var key in jsonObj) {
        if (!qtObj.hasOwnProperty(key)) continue;

        // Check if the property is a QtObject (not a value)
        var value = qtObj[key];
        var jsonValue = jsonObj[key];

        // If it's a QtObject (has objectName property), recurse into it
        // Plain JS objects (property var) should be assigned directly
        if (value && typeof value === "object" && !Array.isArray(value) &&
            value.hasOwnProperty("objectName")) {
            applyToQtObject(value, jsonValue);
        } else {
            // Assign the value directly (covers primitives, arrays, and plain JS objects)
            qtObj[key] = jsonValue;
        }
    }
}
