// BooruApiTypes.js - Shared API family mappers
// Reduces code duplication by defining mapFunc once per API type
// IMPORTANT: Must use ES5 syntax (no arrow functions, const, let, template strings)

.pragma library

// Helper function to get a working image source
function getWorkingImageSource(source) {
    if (!source) return null
    // Skip twitter/x sources as they don't load directly
    if (source.indexOf("twitter.com") >= 0 || source.indexOf("x.com") >= 0) return null
    // Skip pixiv sources as they require referer
    if (source.indexOf("pixiv.net") >= 0 || source.indexOf("pximg.net") >= 0) return null
    return source
}

// Helper function to extract file extension from URL (strips query parameters)
// Handles signed URLs like: https://example.com/file.mp4?token=abc123
function getFileExtFromUrl(url) {
    if (!url) return "jpg"
    var queryIdx = url.indexOf('?')
    if (queryIdx > 0) url = url.substring(0, queryIdx)
    var ext = url.split('.').pop()
    return ext ? ext.toLowerCase() : "jpg"
}

// =============================================================================
// API Family: Moebooru
// Providers: yandere, konachan, lolibooru, sakugabooru
// =============================================================================
var moebooru = {
    mapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            if (!item.file_url) continue
            result.push({
                id: item.id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: item.tags || "",
                rating: item.rating || "s",
                is_nsfw: (item.rating !== "s"),
                md5: item.md5 || "",
                preview_url: item.preview_url || item.file_url,
                sample_url: item.sample_url || item.file_url,
                file_url: item.file_url,
                file_ext: item.file_ext || getFileExtFromUrl(item.file_url),
                source: getWorkingImageSource(item.source) || item.file_url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            result.push({ name: item.name || "", count: item.count || 0 })
        }
        return result
    }
}

// =============================================================================
// API Family: Danbooru
// Providers: danbooru, aibooru
// Field differences: image_width/height, tag_string, is_deleted, is_banned
// =============================================================================
var danbooru = {
    mapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            // Skip deleted/banned posts and those without URLs
            if (!item.file_url || item.is_deleted || item.is_banned) continue
            result.push({
                id: item.id,
                width: item.image_width,
                height: item.image_height,
                aspect_ratio: item.image_width / item.image_height,
                tags: item.tag_string,
                rating: item.rating,
                is_nsfw: (item.rating === "q" || item.rating === "e"),
                md5: item.md5,
                preview_url: item.preview_file_url,
                sample_url: item.large_file_url ? item.large_file_url : item.file_url,
                file_url: item.file_url,
                file_ext: item.file_ext,
                source: getWorkingImageSource(item.source) || item.file_url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            result.push({ name: item.name || "", count: item.post_count || 0 })
        }
        return result
    }
}

// =============================================================================
// API Family: Gelbooru 0.2
// Providers: gelbooru, safebooru, rule34, xbooru, tbib, hypnohub
// Variations: .post wrapper (gelbooru), direct array (others), custom URLs (tbib)
// =============================================================================
var gelbooru = {
    // Standard gelbooru with .post wrapper
    mapFunc: function(response) {
        // Handle .post wrapper (gelbooru.com) or direct array (others)
        var posts = (response && response.post) ? response.post : response
        if (!posts || !Array.isArray(posts)) return []
        var result = []
        for (var i = 0; i < posts.length; i++) {
            var item = posts[i]
            if (!item.file_url) continue
            var rating = (item.rating && item.rating.length > 0)
                ? item.rating.replace("general", "s").charAt(0)
                : "s"
            result.push({
                id: item.id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: item.tags || "",
                rating: rating,
                is_nsfw: (rating !== "s"),
                md5: item.md5 || item.hash || "",
                preview_url: item.preview_url || item.file_url,
                sample_url: item.sample_url || item.file_url,
                file_url: item.file_url,
                file_ext: getFileExtFromUrl(item.file_url),
                source: getWorkingImageSource(item.source) || item.file_url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        // Handle .tag wrapper or direct array
        var tags = (response && response.tag) ? response.tag : response
        if (!tags || !Array.isArray(tags)) return []
        var result = []
        for (var i = 0; i < tags.length; i++) {
            var item = tags[i]
            result.push({ name: item.name || "", count: item.count || 0 })
        }
        return result
    },
    // Autocomplete format (safebooru, rule34 style)
    tagMapFuncAutocomplete: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            var count = 0
            if (item && item.label) {
                var match = item.label.match(/\((\d+)\)/)
                if (match && match[1]) count = parseInt(match[1])
            }
            result.push({ name: (item && item.value) ? item.value : "", count: count })
        }
        return result
    }
}

// NSFW-only variant (rule34, xbooru, hypnohub)
var gelbooruNsfw = {
    mapFunc: function(response) {
        // Rule34 returns error string on auth failure
        if (typeof response === "string") {
            console.log("[Booru] Gelbooru auth error: " + response)
            return []
        }
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            if (!item.file_url) continue
            result.push({
                id: item.id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: item.tags || "",
                rating: "e",
                is_nsfw: true,
                md5: item.md5 || item.hash || "",
                preview_url: item.preview_url || item.file_url,
                sample_url: item.sample_url || item.file_url,
                file_url: item.file_url,
                file_ext: getFileExtFromUrl(item.file_url),
                source: getWorkingImageSource(item.source) || item.file_url
            })
        }
        return result
    },
    tagMapFunc: gelbooru.tagMapFuncAutocomplete
}

// =============================================================================
// API Family: e621
// Providers: e621, e926
// Features: .posts wrapper, categorized tags (general, species, character, artist, copyright)
// =============================================================================
var e621 = {
    mapFunc: function(response, config) {
        if (!response || !response.posts || !Array.isArray(response.posts)) return []
        var result = []
        var isSfwOnly = config && config.sfwOnly
        for (var i = 0; i < response.posts.length; i++) {
            var item = response.posts[i]
            if (!item || !item.file || !item.file.url) continue
            // Concatenate all tag categories
            var allTags = ""
            if (item.tags) {
                var tagParts = []
                if (item.tags.general && Array.isArray(item.tags.general))
                    tagParts = tagParts.concat(item.tags.general)
                if (item.tags.species && Array.isArray(item.tags.species))
                    tagParts = tagParts.concat(item.tags.species)
                if (item.tags.character && Array.isArray(item.tags.character))
                    tagParts = tagParts.concat(item.tags.character)
                if (item.tags.artist && Array.isArray(item.tags.artist))
                    tagParts = tagParts.concat(item.tags.artist)
                if (item.tags.copyright && Array.isArray(item.tags.copyright))
                    tagParts = tagParts.concat(item.tags.copyright)
                allTags = tagParts.join(" ")
            }
            var sourceUrl = (item.sources && item.sources.length > 0) ? item.sources[0] : null
            result.push({
                id: item.id,
                width: item.file.width || 0,
                height: item.file.height || 0,
                aspect_ratio: (item.file.width && item.file.height) ? item.file.width / item.file.height : 1,
                tags: allTags,
                rating: item.rating || "s",
                is_nsfw: isSfwOnly ? false : (item.rating === "q" || item.rating === "e"),
                md5: item.file.md5 || "",
                preview_url: (item.preview && item.preview.url) ? item.preview.url : item.file.url,
                sample_url: (item.sample && item.sample.url) ? item.sample.url : item.file.url,
                file_url: item.file.url,
                file_ext: item.file.ext || "jpg",
                source: getWorkingImageSource(sourceUrl) || item.file.url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            result.push({ name: item.name || "", count: item.post_count || 0 })
        }
        return result
    }
}

// =============================================================================
// API Family: Philomena
// Providers: derpibooru, furbooru, ponybooru
// Features: .images wrapper, tags as array
// =============================================================================
var philomena = {
    mapFunc: function(response) {
        if (!response || !response.images || !Array.isArray(response.images)) return []
        var result = []
        for (var i = 0; i < response.images.length; i++) {
            var item = response.images[i]
            if (!item || !item.view_url) continue
            // Tags are already an array
            var tagString = (item.tags && Array.isArray(item.tags)) ? item.tags.join(" ") : ""
            // Philomena uses "safe", "suggestive", "questionable", "explicit"
            var rating = "s"
            if (item.tags) {
                if (item.tags.indexOf("explicit") >= 0) rating = "e"
                else if (item.tags.indexOf("questionable") >= 0) rating = "q"
                else if (item.tags.indexOf("suggestive") >= 0) rating = "q"
            }
            result.push({
                id: item.id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: tagString,
                rating: rating,
                is_nsfw: (rating === "q" || rating === "e"),
                md5: item.sha512_hash ? item.sha512_hash.substring(0, 32) : "",
                preview_url: item.representations ? item.representations.thumb : item.view_url,
                sample_url: item.representations ? item.representations.large : item.view_url,
                file_url: item.view_url,
                file_ext: item.format || getFileExtFromUrl(item.view_url),
                source: (item.source_url && item.source_url.length > 0) ? item.source_url : item.view_url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !response.tags || !Array.isArray(response.tags)) return []
        var result = []
        for (var i = 0; i < response.tags.length; i++) {
            var item = response.tags[i]
            result.push({ name: item.name || item.slug || "", count: item.images || 0 })
        }
        return result
    }
}

// =============================================================================
// API Family: Shimmie (XML)
// Providers: paheal
// Features: XML response, getElementsByTagName
// =============================================================================
var shimmie = {
    mapFunc: function(xmlDoc) {
        if (!xmlDoc) return []
        var result = []
        var posts = xmlDoc.getElementsByTagName("tag")
        if (!posts) return []
        for (var i = 0; i < posts.length; i++) {
            var item = posts[i]
            var fileUrl = item.getAttribute("file_url")
            if (!fileUrl) continue
            var previewPath = item.getAttribute("preview_url")
            var previewUrl = (previewPath && previewPath.indexOf("http") === 0)
                ? previewPath
                : "https://rule34.paheal.net" + (previewPath || "")
            var fileName = item.getAttribute("file_name") || "unknown.jpg"
            var width = parseInt(item.getAttribute("width")) || 0
            var height = parseInt(item.getAttribute("height")) || 0
            result.push({
                id: parseInt(item.getAttribute("id")) || 0,
                width: width,
                height: height,
                aspect_ratio: (width && height) ? width / height : 1,
                tags: item.getAttribute("tags") || "",
                rating: "e",
                is_nsfw: true,
                md5: item.getAttribute("md5") || "",
                preview_url: previewUrl,
                sample_url: fileUrl,
                file_url: fileUrl,
                file_ext: getFileExtFromUrl(fileName),
                source: fileUrl
            })
        }
        return result
    }
}

// =============================================================================
// API Family: Wallhaven
// Providers: wallhaven
// Features: .data wrapper, dimension_x/y, purity field, tags as objects
// =============================================================================
var wallhaven = {
    mapFunc: function(response) {
        if (!response || !response.data || !Array.isArray(response.data)) return []
        var result = []
        for (var i = 0; i < response.data.length; i++) {
            var item = response.data[i]
            if (!item || !item.path) continue
            // Extract tag names
            var tagNames = ""
            if (item.tags && Array.isArray(item.tags)) {
                var names = []
                for (var j = 0; j < item.tags.length; j++) {
                    if (item.tags[j] && item.tags[j].name) names.push(item.tags[j].name)
                }
                tagNames = names.join(" ")
            }
            result.push({
                id: item.id || i,
                width: item.dimension_x || 0,
                height: item.dimension_y || 0,
                aspect_ratio: (item.dimension_x && item.dimension_y) ? item.dimension_x / item.dimension_y : 1,
                tags: tagNames,
                rating: item.purity === "sfw" ? "s" : (item.purity === "sketchy" ? "q" : "e"),
                is_nsfw: item.purity === "nsfw",
                md5: item.id || "",
                preview_url: (item.thumbs && item.thumbs.small) ? item.thumbs.small : item.path,
                sample_url: (item.thumbs && item.thumbs.large) ? item.thumbs.large : item.path,
                file_url: item.path,
                file_ext: getFileExtFromUrl(item.path),
                source: item.source || item.path
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        // Wallhaven doesn't have a proper tag search endpoint
        return []
    }
}

// =============================================================================
// API Family: waifu.im
// Features: .images wrapper, tags as objects with name property
// =============================================================================
var waifuIm = {
    mapFunc: function(response) {
        if (!response || !response.images || !Array.isArray(response.images)) return []
        var result = []
        for (var i = 0; i < response.images.length; i++) {
            var item = response.images[i]
            if (!item.url) continue
            // Extract tag names
            var tagNames = ""
            if (item.tags && Array.isArray(item.tags)) {
                var names = []
                for (var j = 0; j < item.tags.length; j++) {
                    if (item.tags[j] && item.tags[j].name) names.push(item.tags[j].name)
                }
                tagNames = names.join(" ")
            }
            result.push({
                id: item.image_id || i,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: tagNames,
                rating: item.is_nsfw ? "e" : "s",
                is_nsfw: item.is_nsfw || false,
                md5: item.md5 || "",
                preview_url: item.sample_url || item.url,
                sample_url: item.url,
                file_url: item.url,
                file_ext: item.extension || "jpg",
                source: getWorkingImageSource(item.source) || item.url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        // waifu.im returns versatile and nsfw tag arrays
        var result = []
        if (response && response.versatile && Array.isArray(response.versatile)) {
            for (var i = 0; i < response.versatile.length; i++) {
                result.push({ name: response.versatile[i] })
            }
        }
        if (response && response.nsfw && Array.isArray(response.nsfw)) {
            for (var j = 0; j < response.nsfw.length; j++) {
                result.push({ name: response.nsfw[j] })
            }
        }
        return result
    }
}

// =============================================================================
// API Family: nekos.best
// Features: .results wrapper, minimal metadata
// =============================================================================
var nekosBest = {
    mapFunc: function(response) {
        if (!response || !response.results || !Array.isArray(response.results)) return []
        var result = []
        for (var i = 0; i < response.results.length; i++) {
            var item = response.results[i]
            if (!item || !item.url) continue
            var ext = getFileExtFromUrl(item.url)
            // Extract filename without extension for md5
            var urlPath = item.url.indexOf('?') > 0 ? item.url.substring(0, item.url.indexOf('?')) : item.url
            var filename = urlPath.split("/").pop().replace("." + ext, "")
            result.push({
                id: i,
                width: 1000,  // nekos.best doesn't provide dimensions
                height: 1000,
                aspect_ratio: 1,
                tags: "neko anime",
                rating: "s",
                is_nsfw: false,
                md5: filename,
                preview_url: item.url,
                sample_url: item.url,
                file_url: item.url,
                file_ext: ext,
                source: item.source_url || item.url
            })
        }
        return result
    }
}

// =============================================================================
// API Family: Zerochan
// Features: REST JSON, items array, dimensions in object
// =============================================================================
var zerochan = {
    mapFunc: function(response) {
        if (!response || !response.items || !Array.isArray(response.items)) return []
        var result = []
        for (var i = 0; i < response.items.length; i++) {
            var item = response.items[i]
            if (!item) continue

            // Zerochan URL patterns:
            // - Thumbnail (240px): Provided directly in item.thumbnail
            // - Sample (600px): s1.zerochan.net/<tag.dotted>.600.<id>.jpg
            // - Full: static.zerochan.net/<tag.dotted>.full.<id>.<ext>
            // NOTE: Full images can be .jpg, .png, .jpeg, or .webp - API doesn't specify which!
            var mainTag = (item.tag || "Image").replace(/ /g, ".")
            var id = item.id || i
            var previewUrl = item.thumbnail || ("https://s3.zerochan.net/240/00/00/" + id + ".jpg")
            var sampleUrl = "https://s1.zerochan.net/" + mainTag + ".600." + id + ".jpg"
            var baseFullUrl = "https://static.zerochan.net/" + mainTag + ".full." + id
            // Try jpg first (most common), then fallback to other extensions
            // Order by frequency: jpg > png > gif > jpeg > webp
            var fullUrlJpg = baseFullUrl + ".jpg"
            var fallbackExts = [".png", ".gif", ".jpeg", ".webp"]

            // Tags: combine main tag + tags array
            var tags = ""
            if (item.tag) tags = item.tag
            if (item.tags && Array.isArray(item.tags)) {
                tags = tags ? (tags + " " + item.tags.join(" ")) : item.tags.join(" ")
            }

            // Build array of fallback URLs for all extension variants
            var fallbacks = []
            for (var j = 0; j < fallbackExts.length; j++) {
                fallbacks.push(baseFullUrl + fallbackExts[j])
            }

            result.push({
                id: id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: tags,
                rating: "s",
                is_nsfw: false,
                md5: item.md5 || "",
                preview_url: previewUrl,
                sample_url: sampleUrl,
                file_url: fullUrlJpg,
                file_url_fallbacks: fallbacks,  // Array: [.png, .jpeg, .webp] for zerochan extension guessing
                file_ext: "jpg",
                source: item.source || ("https://www.zerochan.net/" + id)
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            result.push({ name: item.name || item.tag || "", count: item.count || item.total || 0 })
        }
        return result
    }
}

// =============================================================================
// API Family: Sankaku (Beta API)
// Features: Similar to Moebooru but with different field names
// =============================================================================
var sankaku = {
    mapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            // Skip items without URLs or that require login
            // redirect_to_signup: true means URLs are withheld (account required)
            if (!item.file_url || item.file_url.length === 0) continue
            if (item.redirect_to_signup) continue
            // Sankaku tags are objects with name property
            var tagString = ""
            if (item.tags && Array.isArray(item.tags)) {
                var tagNames = []
                for (var j = 0; j < item.tags.length; j++) {
                    if (item.tags[j] && item.tags[j].name) {
                        tagNames.push(item.tags[j].name)
                    }
                }
                tagString = tagNames.join(" ")
            }
            // Determine if this is a video based on file_type or extension
            var fileType = item.file_type || ""
            var ext = item.file_ext || getFileExtFromUrl(item.file_url)
            var isVideo = fileType.indexOf("video") >= 0 || ext === "mp4" || ext === "webm"

            // For images: Use sample_url (WebP) for fast preview (Qt doesn't support AVIF)
            // For videos: Keep original preview_url (AVIF) - we'll convert with avifdec
            var previewUrl = isVideo ? (item.preview_url || item.file_url) : (item.sample_url || item.file_url)

            result.push({
                id: item.id,
                width: item.width || 0,
                height: item.height || 0,
                aspect_ratio: (item.width && item.height) ? item.width / item.height : 1,
                tags: tagString,
                rating: item.rating || "s",
                is_nsfw: (item.rating !== "s"),
                md5: item.md5 || "",
                preview_url: previewUrl,
                sample_url: item.sample_url || item.file_url,
                file_url: item.file_url,
                file_ext: ext,
                file_size: item.file_size || 0,  // For download progress indication
                source: getWorkingImageSource(item.source) || item.file_url
            })
        }
        return result
    },
    tagMapFunc: function(response) {
        if (!response || !Array.isArray(response)) return []
        var result = []
        for (var i = 0; i < response.length; i++) {
            var item = response[i]
            result.push({ name: item.name || "", count: item.count || item.post_count || 0 })
        }
        return result
    }
}

// =============================================================================
// Export all API types
// =============================================================================
var BooruApiTypes = {
    moebooru: moebooru,
    danbooru: danbooru,
    gelbooru: gelbooru,
    gelbooruNsfw: gelbooruNsfw,
    e621: e621,
    philomena: philomena,
    shimmie: shimmie,
    wallhaven: wallhaven,
    waifuIm: waifuIm,
    nekosBest: nekosBest,
    zerochan: zerochan,
    sankaku: sankaku
}
