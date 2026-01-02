pragma Singleton
pragma ComponentBehavior: Bound

import "../modules/common"
import QtQuick
import Quickshell

/**
 * A service for interacting with various booru APIs.
 * Simplified version adapted from end-4/dots-hyprland
 */
Singleton {
    id: root

    Component.onCompleted: {
        console.log("=== BOORU SERVICE LOADED ===")
        console.log("Provider count: " + providerList.length)
        console.log("Providers: " + providerList.join(", "))
    }

    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)
    signal responseFinished()

    property string failMessage: "That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number"
    property var responses: []
    property int runningRequests: 0
    property bool replaceOnNextResponse: false  // When true, replace responses instead of appending
    property string defaultUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: {
        var list = Object.keys(providers).filter(function(provider) {
            return provider !== "system" && providers[provider].api
        })
        console.log("[Booru] providerList: " + list.join(", "))
        return list
    }

    // Persistent state
    property string currentProvider: "wallhaven"
    property bool allowNsfw: false
    property int limit: 20

    // Wallhaven sorting options (legacy, kept for backwards compatibility)
    property string wallhavenSorting: "toplist"  // date_added, relevance, random, views, favorites, toplist
    property string wallhavenOrder: "desc"       // desc, asc
    property var wallhavenSortOptions: ["toplist", "random", "date_added", "relevance", "views", "favorites"]

    // Wallhaven toplist time range (only applies when sorting=toplist)
    property string wallhavenTopRange: "1M"  // 1d, 3d, 1w, 1M, 3M, 6M, 1y
    readonly property var topRangeOptions: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]

    // Wallhaven minimum resolution filter
    property string wallhavenResolution: "3840x2160"  // Default: 4K
    readonly property var resolutionOptions: ["1280x720", "1920x1080", "2560x1440", "3840x2160", "any"]
    readonly property var resolutionLabels: ({"1280x720": "720p", "1920x1080": "1080p", "2560x1440": "1440p", "3840x2160": "4K", "any": "Any"})

    // Danbooru age filter (prevents timeout on score/favcount sorting)
    property string danbooruAge: "1month"  // 1day, 1week, 1month, 3months, 1year, any
    readonly property var danbooruAgeOptions: ["1day", "1week", "1month", "3months", "1year", "any"]
    readonly property var danbooruAgeLabels: ({"1day": "1d", "1week": "1w", "1month": "1M", "3months": "3M", "1year": "1y", "any": "All"})

    // Universal sorting - works with all providers that support it
    property string currentSorting: ""  // Empty = provider default

    // Per-provider sort options (empty array = no sorting support)
    property var providerSortOptions: ({
        "yandere": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "konachan": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "konachan_com": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "danbooru": ["rank", "score", "id", "id_desc"],
        "e621": ["score", "favcount", "id"],
        "e926": ["score", "favcount", "id"],
        "gelbooru": ["score", "score:desc", "score:asc", "id", "updated"],
        "safebooru": ["score", "score:desc", "score:asc", "id", "updated"],
        "rule34": ["score", "score:desc", "score:asc", "id", "updated"],
        "wallhaven": ["toplist", "random", "date_added", "relevance", "views", "favorites"],
        "waifu.im": [],
        "nekos_best": [],
        "xbooru": ["score", "id", "updated"],
        "tbib": ["score", "id"],
        "paheal": [],
        "hypnohub": ["score", "id", "updated"],
        "aibooru": ["score", "id"]
    })

    // Get sort options for current provider
    function getSortOptions() {
        var options = providerSortOptions[currentProvider]
        return options ? options : []
    }

    // Check if current provider supports sorting
    property bool providerSupportsSorting: getSortOptions().length > 0

    // SFW-only providers where NSFW toggle doesn't apply
    // safebooru.org, e926.net, nekos.best, konachan.net are all SFW-only by design
    property var sfwOnlyProviders: ["safebooru", "e926", "nekos_best", "konachan"]
    // NSFW-only providers - rating filter doesn't apply (all content is NSFW)
    property var nsfwOnlyProviders: ["rule34", "xbooru", "tbib", "paheal", "hypnohub"]
    property bool providerSupportsNsfw: sfwOnlyProviders.indexOf(currentProvider) === -1

    // Gelbooru API credentials (configured in config.json under "booru")
    // Get your key at: https://gelbooru.com/index.php?page=account&s=options
    property string gelbooruApiKey: (ConfigOptions.booru && ConfigOptions.booru.gelbooruApiKey) ? ConfigOptions.booru.gelbooruApiKey : ""
    property string gelbooruUserId: (ConfigOptions.booru && ConfigOptions.booru.gelbooruUserId) ? ConfigOptions.booru.gelbooruUserId : ""

    // Rule34 API credentials (configured in config.json under "booru")
    // Get your key at: https://rule34.xxx/index.php?page=account&s=options
    property string rule34ApiKey: (ConfigOptions.booru && ConfigOptions.booru.rule34ApiKey) ? ConfigOptions.booru.rule34ApiKey : ""
    property string rule34UserId: (ConfigOptions.booru && ConfigOptions.booru.rule34UserId) ? ConfigOptions.booru.rule34UserId : ""

    // Wallhaven API key (required for NSFW content)
    // Get your key at: https://wallhaven.cc/settings/account
    property string wallhavenApiKey: (ConfigOptions.booru && ConfigOptions.booru.wallhavenApiKey) ? ConfigOptions.booru.wallhavenApiKey : ""

    // Danbooru API credentials (higher rate limits, access to restricted content)
    // Get your key at: https://danbooru.donmai.us/profile → API Key
    property string danbooruLogin: (ConfigOptions.booru && ConfigOptions.booru.danbooruLogin) ? ConfigOptions.booru.danbooruLogin : ""
    property string danbooruApiKey: (ConfigOptions.booru && ConfigOptions.booru.danbooruApiKey) ? ConfigOptions.booru.danbooruApiKey : ""

    property var providers: {
        "system": { "name": "System" },
        "yandere": {
            "name": "yande.re",
            "url": "https://yande.re",
            "api": "https://yande.re/post.json",
            "description": "All-rounder | Good quality, decent quantity",
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.count }
                })
            }
        },
        "konachan": {
            "name": "Konachan",
            "url": "https://konachan.net",
            "api": "https://konachan.net/post.json",
            "description": "For desktop wallpapers | Good quality",
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.count }
                })
            }
        },
        "danbooru": {
            "name": "Danbooru",
            "url": "https://danbooru.donmai.us",
            "api": "https://danbooru.donmai.us/posts.json",
            "description": "The popular one | Best quantity, quality varies",
            "mapFunc": (response) => {
                // Danbooru uses g=general, s=sensitive, q=questionable, e=explicit
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    // Skip deleted/banned posts and those without URLs
                    if (!item.file_url || item.is_deleted || item.is_banned) continue
                    result.push({
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating === 'q' || item.rating === 'e'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.large_file_url ? item.large_file_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://danbooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.post_count }
                })
            }
        },
        "gelbooru": {
            "name": "Gelbooru",
            "url": "https://gelbooru.com",
            "api": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "description": "Great quantity, lots of NSFW, quality varies",
            "mapFunc": (response) => {
                response = response.post
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating.replace('general', 's').charAt(0),
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://gelbooru.com/index.php?page=dapi&s=tag&q=index&json=1&orderby=count&limit=10&name_pattern={{query}}%",
            "tagMapFunc": (response) => {
                return response.tag.map(item => {
                    return { "name": item.name, "count": item.count }
                })
            }
        },
        "waifu.im": {
            "name": "waifu.im",
            "url": "https://waifu.im",
            "api": "https://api.waifu.im/search",
            "description": "Waifus only | Excellent quality, limited quantity",
            "mapFunc": (response) => {
                response = response.images
                return response.map(item => {
                    return {
                        "id": item.image_id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags.map(tag => tag.name).join(" "),
                        "rating": item.is_nsfw ? "e" : "s",
                        "is_nsfw": item.is_nsfw,
                        "md5": item.md5,
                        "preview_url": item.sample_url ? item.sample_url : item.url,
                        "sample_url": item.url,
                        "file_url": item.url,
                        "file_ext": item.extension,
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.url,
                    }
                })
            },
            "tagSearchTemplate": "https://api.waifu.im/tags",
            "tagMapFunc": (response) => {
                // Combine versatile and nsfw tags
                var result = []
                for (var i = 0; i < response.versatile.length; i++) {
                    result.push({name: response.versatile[i]})
                }
                for (var j = 0; j < response.nsfw.length; j++) {
                    result.push({name: response.nsfw[j]})
                }
                return result
            }
        },
        "safebooru": {
            "name": "Safebooru",
            "url": "https://safebooru.org",
            "api": "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1",
            "description": "SFW only | Family-friendly anime images",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item.file_url) continue
                    result.push({
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": "s",
                        "is_nsfw": false,
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": item.source ? item.source : item.file_url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://safebooru.org/autocomplete.php?q={{query}}",
            "tagMapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var count = item.label.match(/\((\d+)\)/)
                    result.push({ "name": item.value, "count": count ? parseInt(count[1]) : 0 })
                }
                return result
            }
        },
        "rule34": {
            "name": "Rule34",
            "url": "https://rule34.xxx",
            "api": "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1",
            "description": "NSFW | Requires API key (rule34.xxx/account)",
            "mapFunc": (response) => {
                // API returns error string when auth fails
                if (typeof response === 'string' || !Array.isArray(response)) {
                    console.log("[Booru] Rule34 auth error: " + response)
                    return []
                }
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item.file_url) continue
                    result.push({
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": "e",
                        "is_nsfw": true,
                        "md5": item.md5 ? item.md5 : item.hash,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://api.rule34.xxx/autocomplete.php?q={{query}}",
            "tagMapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var count = 0
                    if (item.label) {
                        var match = item.label.match(/\((\d+)\)/)
                        if (match && match[1]) count = parseInt(match[1])
                    }
                    result.push({ "name": item.value, "count": count })
                }
                return result
            }
        },
        "e621": {
            "name": "e621",
            "url": "https://e621.net",
            "api": "https://e621.net/posts.json",
            "description": "Furry artwork | NSFW, requires User-Agent",
            "mapFunc": (response) => {
                // e621 uses s=safe, q=questionable, e=explicit
                var result = []
                for (var i = 0; i < response.posts.length; i++) {
                    var item = response.posts[i]
                    if (!item.file.url) continue
                    // Concatenate all tag categories
                    var allTags = item.tags.general.concat(
                        item.tags.species,
                        item.tags.character,
                        item.tags.artist,
                        item.tags.copyright
                    ).join(" ")
                    var sourceUrl = (item.sources && item.sources.length > 0) ? item.sources[0] : null
                    result.push({
                        "id": item.id,
                        "width": item.file.width,
                        "height": item.file.height,
                        "aspect_ratio": item.file.width / item.file.height,
                        "tags": allTags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating === 'q' || item.rating === 'e'),
                        "md5": item.file.md5,
                        "preview_url": item.preview.url,
                        "sample_url": item.sample.url ? item.sample.url : item.file.url,
                        "file_url": item.file.url,
                        "file_ext": item.file.ext,
                        "source": getWorkingImageSource(sourceUrl) ? getWorkingImageSource(sourceUrl) : item.file.url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://e621.net/tags.json?limit=10&search[name_matches]={{query}}*&search[order]=count",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.post_count }
                })
            }
        },
        "e926": {
            "name": "e926",
            "url": "https://e926.net",
            "api": "https://e926.net/posts.json",
            "description": "Furry artwork | SFW only version of e621",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.posts.length; i++) {
                    var item = response.posts[i]
                    if (!item.file.url) continue
                    // Concatenate all tag categories
                    var allTags = item.tags.general.concat(
                        item.tags.species,
                        item.tags.character,
                        item.tags.artist,
                        item.tags.copyright
                    ).join(" ")
                    var sourceUrl = (item.sources && item.sources.length > 0) ? item.sources[0] : null
                    result.push({
                        "id": item.id,
                        "width": item.file.width,
                        "height": item.file.height,
                        "aspect_ratio": item.file.width / item.file.height,
                        "tags": allTags,
                        "rating": item.rating,
                        "is_nsfw": false,
                        "md5": item.file.md5,
                        "preview_url": item.preview.url,
                        "sample_url": item.sample.url ? item.sample.url : item.file.url,
                        "file_url": item.file.url,
                        "file_ext": item.file.ext,
                        "source": getWorkingImageSource(sourceUrl) ? getWorkingImageSource(sourceUrl) : item.file.url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://e926.net/tags.json?limit=10&search[name_matches]={{query}}*&search[order]=count",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.post_count }
                })
            }
        },
        "wallhaven": {
            "name": "Wallhaven",
            "url": "https://wallhaven.cc",
            "api": "https://wallhaven.cc/api/v1/search",
            "description": "Desktop wallpapers | High quality, all resolutions",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.data.length; i++) {
                    var item = response.data[i]
                    // Extract tag names if tags array exists
                    var tagNames = ""
                    if (item.tags && item.tags.length > 0) {
                        var names = []
                        for (var j = 0; j < item.tags.length; j++) {
                            names.push(item.tags[j].name)
                        }
                        tagNames = names.join(" ")
                    }
                    result.push({
                        "id": item.id,
                        "width": item.dimension_x,
                        "height": item.dimension_y,
                        "aspect_ratio": item.dimension_x / item.dimension_y,
                        "tags": tagNames,
                        "rating": item.purity === "sfw" ? "s" : (item.purity === "sketchy" ? "q" : "e"),
                        "is_nsfw": item.purity === "nsfw",
                        "md5": item.id,
                        "preview_url": item.thumbs.small,
                        "sample_url": item.thumbs.large,
                        "file_url": item.path,
                        "file_ext": item.path.split('.').pop(),
                        "source": item.source ? item.source : item.path,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://wallhaven.cc/api/v1/search?q={{query}}&sorting=relevance",
            "tagMapFunc": (response) => {
                // Wallhaven doesn't have a proper tag search, return empty
                return []
            }
        },
        "konachan_com": {
            "name": "Konachan.com",
            "url": "https://konachan.com",
            "api": "https://konachan.com/post.json",
            "description": "For desktop wallpapers | More NSFW than .net",
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ? getWorkingImageSource(item.source) : item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://konachan.com/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.count }
                })
            }
        },
        "nekos_best": {
            "name": "nekos.best",
            "url": "https://nekos.best",
            "api": "https://nekos.best/api/v2/neko",
            "description": "Anime characters | Random images, high quality",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.results.length; i++) {
                    var item = response.results[i]
                    var ext = item.url.split('.').pop()
                    result.push({
                        "id": i,
                        "width": 1000,  // nekos.best doesn't provide dimensions
                        "height": 1000,
                        "aspect_ratio": 1,
                        "tags": "neko anime",
                        "rating": "s",
                        "is_nsfw": false,
                        "md5": item.url.split('/').pop().replace("." + ext, ''),
                        "preview_url": item.url,
                        "sample_url": item.url,
                        "file_url": item.url,
                        "file_ext": ext,
                        "source": item.source_url ? item.source_url : item.url,
                    })
                }
                return result
            }
        },
        "xbooru": {
            "name": "Xbooru",
            "url": "https://xbooru.com",
            "api": "https://xbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "description": "Hentai focused imageboard",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item.file_url) continue
                    result.push({
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating ? item.rating.charAt(0) : "e",
                        "is_nsfw": true,
                        "md5": item.hash,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": item.source ? item.source : item.file_url,
                    })
                }
                return result
            }
        },
        "tbib": {
            "name": "TBIB",
            "url": "https://tbib.org",
            "api": "https://tbib.org/index.php?page=dapi&s=post&q=index&json=1",
            "description": "The Big ImageBoard | 8M+ images aggregator",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var fileUrl = "https://tbib.org/images/" + item.directory + "/" + item.image
                    var previewUrl = "https://tbib.org/thumbnails/" + item.directory + "/thumbnail_" + item.hash + ".jpg"
                    result.push({
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating ? item.rating.charAt(0) : "q",
                        "is_nsfw": (item.rating !== "safe"),
                        "md5": item.hash,
                        "preview_url": previewUrl,
                        "sample_url": fileUrl,
                        "file_url": fileUrl,
                        "file_ext": item.image.split('.').pop(),
                        "source": fileUrl
                    })
                }
                return result
            }
        },
        "paheal": {
            "name": "Paheal Rule34",
            "url": "https://rule34.paheal.net",
            "api": "https://rule34.paheal.net/api/danbooru/find_posts",
            "description": "Rule34 (Shimmie) | 3.5M+ images",
            "isXml": true,
            "mapFunc": (xmlDoc) => {
                var result = []
                var posts = xmlDoc.getElementsByTagName("tag")
                for (var i = 0; i < posts.length; i++) {
                    var item = posts[i]
                    var previewPath = item.getAttribute("preview_url")
                    var previewUrl = (previewPath && previewPath.indexOf("http") === 0) ? previewPath : "https://rule34.paheal.net" + previewPath
                    var fileUrl = item.getAttribute("file_url")
                    var fileName = item.getAttribute("file_name") ? item.getAttribute("file_name") : "unknown.jpg"
                    result.push({
                        "id": parseInt(item.getAttribute("id")),
                        "width": parseInt(item.getAttribute("width")),
                        "height": parseInt(item.getAttribute("height")),
                        "aspect_ratio": parseInt(item.getAttribute("width")) / parseInt(item.getAttribute("height")),
                        "tags": item.getAttribute("tags"),
                        "rating": "e",
                        "is_nsfw": true,
                        "md5": item.getAttribute("md5"),
                        "preview_url": previewUrl,
                        "sample_url": fileUrl,
                        "file_url": fileUrl,
                        "file_ext": fileName.split('.').pop(),
                        "source": fileUrl
                    })
                }
                return result
            }
        },
        "hypnohub": {
            "name": "Hypnohub",
            "url": "https://hypnohub.net",
            "api": "https://hypnohub.net/index.php?page=dapi&s=post&q=index&json=1",
            "description": "Hypnosis/mind control themed | ~92k images",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item.file_url) continue
                    result.push({
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating ? item.rating.charAt(0) : "q",
                        "is_nsfw": true,
                        "md5": item.hash,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ? item.sample_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": item.source ? item.source : item.file_url,
                    })
                }
                return result
            }
        },
        "aibooru": {
            "name": "AIBooru",
            "url": "https://aibooru.online",
            "api": "https://aibooru.online/posts.json",
            "description": "AI-generated art | ~150k images",
            "mapFunc": (response) => {
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item.file_url || item.is_deleted) continue
                    result.push({
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating === 'q' || item.rating === 'e'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.large_file_url ? item.large_file_url : item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": item.source ? item.source : item.file_url,
                    })
                }
                return result
            },
            "tagSearchTemplate": "https://aibooru.online/tags.json?limit=10&search[name_matches]={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return { "name": item.name, "count": item.post_count }
                })
            }
        }
    }

    function getWorkingImageSource(url) {
        if (!url) return null;
        if (url.includes('pximg.net')) {
            var filename = url.substring(url.lastIndexOf('/') + 1)
            var artworkId = filename.replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')
            return "https://www.pixiv.net/en/artworks/" + artworkId
        }
        return url;
    }

    function setProvider(provider) {
        provider = provider.toLowerCase()
        if (providerList.indexOf(provider) !== -1) {
            root.currentProvider = provider
            var msg = "Provider set to " + providers[provider].name
            if (provider === "gelbooru" && (!gelbooruApiKey || !gelbooruUserId)) {
                msg += "\n⚠️ Gelbooru requires API key. Get yours at:\ngelbooru.com/index.php?page=account&s=options"
            }
            if (provider === "rule34" && (!rule34ApiKey || !rule34UserId)) {
                msg += "\n⚠️ Rule34 requires API key. Get yours at:\nrule34.xxx/index.php?page=account&s=options"
            }
            root.addSystemMessage(msg)
        } else {
            root.addSystemMessage("Invalid API provider. Supported:\n- " + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        responses = []
    }

    function addSystemMessage(message) {
        responses = responses.concat([root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": message
        })])
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1) {
        var provider = providers[currentProvider]
        var baseUrl = provider.api
        var url = baseUrl
        var tagString = tags.join(" ")

        // Inject sort metatag for providers that use tag-based sorting
        if (currentSorting && currentSorting.length > 0) {
            // Moebooru sites (yandere, konachan, konachan_com) use order:X
            if (currentProvider === "yandere" || currentProvider === "konachan" || currentProvider === "konachan_com") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Danbooru uses order:X
            else if (currentProvider === "danbooru") {
                tagString = "order:" + currentSorting + " " + tagString
                // Add age filter if not "any" (prevents timeout on heavy sorts)
                if (danbooruAge !== "any") {
                    tagString = tagString + " age:<" + danbooruAge
                }
            }
            // e621/e926 use order:X
            else if (currentProvider === "e621" || currentProvider === "e926") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Gelbooru-based sites use sort:X
            else if (currentProvider === "gelbooru" || currentProvider === "safebooru" || currentProvider === "rule34" || currentProvider === "xbooru" || currentProvider === "tbib" || currentProvider === "hypnohub") {
                tagString = "sort:" + currentSorting + " " + tagString
            }
            // AIBooru uses order:X (Danbooru-style)
            else if (currentProvider === "aibooru") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Wallhaven handled separately via URL params below
        }

        // Handle NSFW filtering per provider
        // Skip for SFW-only providers, NSFW-only providers, and those with own params (waifu.im)
        var skipNsfwFilter = (currentProvider === "waifu.im" ||
                              sfwOnlyProviders.indexOf(currentProvider) !== -1 ||
                              nsfwOnlyProviders.indexOf(currentProvider) !== -1)
        if (!nsfw && !skipNsfwFilter) {
            if (currentProvider == "gelbooru" || currentProvider == "danbooru" || currentProvider == "rule34" || currentProvider == "aibooru")
                tagString += " rating:general";
            else if (currentProvider == "e621")
                tagString += " rating:s";
            else if (currentProvider == "wallhaven")
                {} // Handled via purity parameter
            else
                tagString += " rating:safe";
        }

        var params = []
        if (currentProvider === "waifu.im") {
            var tagsArray = tagString.split(" ");
            tagsArray.forEach(tag => {
                if (tag.length > 0) params.push("included_tags=" + encodeURIComponent(tag));
            });
            params.push("limit=" + Math.min(limit, 30))
            params.push("is_nsfw=" + (nsfw ? "null" : "false"))
        } else if (currentProvider === "wallhaven") {
            // Wallhaven uses different parameter names
            params.push("q=" + encodeURIComponent(tagString))
            // purity: 100=sfw, 010=sketchy, 001=nsfw, combine for multiple
            params.push("purity=" + (nsfw ? "111" : "100"))
            // Use currentSorting if set, otherwise fall back to wallhavenSorting
            var sorting = (currentSorting && currentSorting.length > 0) ? currentSorting : wallhavenSorting
            params.push("sorting=" + sorting)
            params.push("order=" + wallhavenOrder)
            // Add topRange for toplist sorting
            if (sorting === "toplist") {
                params.push("topRange=" + wallhavenTopRange)
            }
            // Minimum resolution filter (skip if "any")
            if (wallhavenResolution !== "any") {
                params.push("atleast=" + wallhavenResolution)
            }
            params.push("page=" + page)
            // API key required for NSFW content
            if (wallhavenApiKey && wallhavenApiKey.length > 0) {
                params.push("apikey=" + wallhavenApiKey)
            }
        } else if (currentProvider === "nekos_best") {
            // nekos.best uses amount parameter, ignores tags
            params.push("amount=" + Math.min(limit, 20))
        } else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            // Providers using pid (page id) instead of page number
            if (currentProvider == "gelbooru" || currentProvider == "safebooru" || currentProvider == "rule34" || currentProvider == "xbooru" || currentProvider == "tbib" || currentProvider == "hypnohub") {
                params.push("pid=" + page)
                // Gelbooru-style API key authentication
                if (currentProvider == "gelbooru" && gelbooruApiKey && gelbooruUserId) {
                    params.push("api_key=" + gelbooruApiKey)
                    params.push("user_id=" + gelbooruUserId)
                }
                if (currentProvider == "rule34" && rule34ApiKey && rule34UserId) {
                    params.push("api_key=" + rule34ApiKey)
                    params.push("user_id=" + rule34UserId)
                }
            } else {
                params.push("page=" + page)
                // Danbooru API key authentication (higher rate limits)
                if (currentProvider == "danbooru" && danbooruApiKey) {
                    if (danbooruLogin) {
                        params.push("login=" + danbooruLogin)
                    }
                    params.push("api_key=" + danbooruApiKey)
                }
            }
        }

        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")
        } else {
            url += "&" + params.join("&")
        }
        return url
    }

    function makeRequest(tags, nsfw=false, limit=20, page=1) {
        // Clear existing results on new search (page 1)
        if (page === 1) {
            clearResponses()
        }
        var url = constructRequestUrl(tags, nsfw, limit, page)
        console.log("[Booru] " + currentProvider + " request: " + url)
        if (currentProvider == "rule34") {
            console.log("[Booru] Rule34 API key: " + (rule34ApiKey ? "set (" + rule34ApiKey.substring(0,8) + "...)" : "NOT SET"))
            console.log("[Booru] Rule34 User ID: " + (rule34UserId ? rule34UserId : "NOT SET"))
        }

        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": currentProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var xhr = new XMLHttpRequest()
        var requestProvider = currentProvider  // Capture provider at request time
        xhr.open("GET", url)
        // Danbooru/e621/e926 need User-Agent or Cloudflare blocks them
        if (requestProvider == "danbooru" || requestProvider == "e621" || requestProvider == "e926") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                console.log("[Booru] Could not set User-Agent for " + requestProvider)
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] " + requestProvider + " done - HTTP " + xhr.status)
            }
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var provider = providers[requestProvider]
                    var response
                    // Handle XML responses (e.g., Paheal)
                    if (provider.isXml) {
                        response = xhr.responseXML
                        console.log("[Booru] " + requestProvider + " got XML response")
                    } else {
                        response = JSON.parse(xhr.responseText)
                        console.log("[Booru] " + requestProvider + " got " + (response.length || "?") + " raw items")
                    }
                    response = provider.mapFunc(response)
                    console.log("[Booru] " + requestProvider + " mapped to " + response.length + " items")
                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                } catch (e) {
                    console.log("[Booru] Failed to parse " + requestProvider + ": " + e)
                    newResponse.message = root.failMessage
                } finally {
                    root.runningRequests--;
                    if (root.replaceOnNextResponse) {
                        root.responses = [newResponse]
                        root.replaceOnNextResponse = false
                    } else {
                        root.responses = root.responses.concat([newResponse])
                    }
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] " + requestProvider + " failed - HTTP " + xhr.status)
                if (xhr.responseText) console.log("[Booru] Response: " + xhr.responseText.substring(0, 200))
                newResponse.message = root.failMessage
                root.runningRequests--;
                if (root.replaceOnNextResponse) {
                    root.responses = [newResponse]
                    root.replaceOnNextResponse = false
                } else {
                    root.responses = root.responses.concat([newResponse])
                }
            }
            root.responseFinished()
        }

        root.runningRequests++;
        xhr.send()
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (!provider.tagSearchTemplate) return

        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        // Add API credentials for tag search
        if (currentProvider === "gelbooru" && gelbooruApiKey && gelbooruUserId) {
            url += "&api_key=" + gelbooruApiKey + "&user_id=" + gelbooruUserId
        }
        if (currentProvider === "rule34" && rule34ApiKey && rule34UserId) {
            url += "&api_key=" + rule34ApiKey + "&user_id=" + rule34UserId
        }
        if (currentProvider === "danbooru" && danbooruApiKey) {
            url += (danbooruLogin ? "&login=" + danbooruLogin : "") + "&api_key=" + danbooruApiKey
        }

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        // Danbooru/e621/e926 need User-Agent or Cloudflare blocks them
        if (currentProvider == "danbooru" || currentProvider == "e621" || currentProvider == "e926") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                console.log("[Booru] Could not set User-Agent for tag search: " + e)
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    var response = JSON.parse(xhr.responseText)
                    response = provider.tagMapFunc(response)
                    root.tagSuggestion(query, response)
                } catch (e) {
                    console.log("[Booru] Failed to parse tag response: " + e)
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Tag search failed - HTTP " + xhr.status)
                currentTagRequest = null
            }
        }
        xhr.send()
    }
}
