pragma Singleton
import QtQuick
import Quickshell
import "../BooruApiTypes.js" as ApiTypes

/**
 * ProviderRegistry - Static provider definitions and metadata.
 *
 * This singleton holds all provider configurations, sort options, and
 * stateless helper functions. Runtime state (current provider, mirrors)
 * remains in Booru.qml.
 *
 * Architecture:
 * - ProviderRegistry: Static data, stateless functions
 * - Booru.qml: Runtime state, API requests, response handling
 */
Singleton {
    id: root

    // =========================================================================
    // Provider List
    // =========================================================================

    readonly property var providerList: [
        "yandere", "konachan", "sakugabooru", "danbooru", "gelbooru",
        "waifu.im", "safebooru", "rule34", "e621", "wallhaven",
        "nekos_best", "xbooru", "tbib", "paheal", "hypnohub",
        "aibooru", "zerochan", "sankaku", "idol_sankaku", "derpibooru",
        "3dbooru", "anime_pictures", "e_shuushuu"
    ]

    // =========================================================================
    // Provider Categories
    // =========================================================================

    // Providers that support the age: metatag (Danbooru/Moebooru with date indexing)
    // Note: sakugabooru and 3dbooru do NOT support age: metatag despite being Moebooru
    readonly property var ageFilterProviders: ["danbooru", "aibooru", "yandere", "konachan"]

    // SFW-only providers where NSFW toggle doesn't apply
    readonly property var sfwOnlyProviders: ["safebooru", "nekos_best", "zerochan"]

    // NSFW-only providers - rating filter doesn't apply (all content is NSFW)
    readonly property var nsfwOnlyProviders: ["rule34", "xbooru", "tbib", "paheal", "hypnohub"]

    // Providers that require curl (User-Agent header needed, XHR can't set it)
    readonly property var curlProviders: ["zerochan"]

    // Providers that prefer Grabber over direct API (bypasses User-Agent/Cloudflare issues)
    readonly property var grabberPreferredProviders: ["danbooru"]

    // =========================================================================
    // Grabber Source Mappings
    // =========================================================================

    // Maps our provider keys to Grabber's expected source names
    readonly property var grabberSources: ({
        "yandere": "yande.re",
        "konachan": "konachan.com",      // Uses .com mirror for Grabber
        "sakugabooru": "www.sakugabooru.com",
        "danbooru": "danbooru.donmai.us",
        "gelbooru": "gelbooru.com",
        "safebooru": "safebooru.org",
        "rule34": "api.rule34.xxx",
        "e621": "e621.net",
        "wallhaven": "wallhaven.cc",
        "xbooru": "xbooru.com",
        "hypnohub": "hypnohub.net",
        "aibooru": "aibooru.online",
        "zerochan": "www.zerochan.net",
        "sankaku": "chan.sankakucomplex.com",
        "idol_sankaku": "idol.sankakucomplex.com",
        "derpibooru": "derpibooru.org",
        "3dbooru": "behoimi.org",
        "anime_pictures": "anime-pictures.net",
        "e_shuushuu": "e-shuushuu.net"
        // Note: waifu.im, nekos_best, tbib, paheal not supported by Grabber
    })

    // =========================================================================
    // Sort Options per Provider
    // =========================================================================

    readonly property var providerSortOptions: ({
        // Moebooru (order: metatag) - yande.re, konachan, sakugabooru, 3dbooru
        "yandere": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "konachan": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "sakugabooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "3dbooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],

        // Danbooru (order: metatag)
        "danbooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],
        "aibooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],

        // e621 (order: metatag) - e926 is now a mirror of e621
        "e621": ["score", "favcount", "random", "id", "id_asc", "comment_count", "tagcount", "mpixels", "filesize", "landscape", "portrait"],

        // Gelbooru-style (sort: metatag)
        "gelbooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "safebooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "rule34": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "xbooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "tbib": ["score", "score:asc", "score:desc", "id", "id:asc", "updated"],
        "hypnohub": ["score", "score:asc", "score:desc", "id", "id:asc", "updated"],

        // Wallhaven (URL params)
        "wallhaven": ["toplist", "random", "date_added", "relevance", "views", "favorites", "hot"],

        // Zerochan (s param)
        "zerochan": ["id", "fav"],

        // Sankaku (order: metatag) - NOTE: favcount causes API timeout errors
        "sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],
        "idol_sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],

        // Derpibooru (sf param)
        "derpibooru": ["score", "wilson_score", "relevance", "random", "created_at", "updated_at", "first_seen_at", "width", "height", "comment_count", "tag_count"],

        // No sorting support
        "waifu.im": [],
        "nekos_best": [],
        "paheal": []
    })

    // =========================================================================
    // Provider Definitions
    // =========================================================================

    readonly property var providers: ({
        "system": { "name": "System" },
        "yandere": {
            "name": "yande.re",
            "url": "https://yande.re",
            "api": "https://yande.re/post.json",
            "apiType": "moebooru",
            "description": "All-rounder | Good quality, decent quantity",
            "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=10&name={{query}}*"
        },
        "konachan": {
            "name": "Konachan",
            "url": "https://konachan.net",
            "api": "https://konachan.net/post.json",
            "apiType": "moebooru",
            "description": "For desktop wallpapers | Good quality",
            "mirrors": {
                "konachan.net": {
                    "url": "https://konachan.net",
                    "api": "https://konachan.net/post.json",
                    "tagApi": "https://konachan.net/tag.json",
                    "description": "SFW-focused",
                    "sfwOnly": true
                },
                "konachan.com": {
                    "url": "https://konachan.com",
                    "api": "https://konachan.com/post.json",
                    "tagApi": "https://konachan.com/tag.json",
                    "description": "More NSFW",
                    "sfwOnly": false
                }
            },
            "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=10&name={{query}}*"
        },
        "sakugabooru": {
            "name": "Sakugabooru",
            "url": "https://www.sakugabooru.com",
            "api": "https://www.sakugabooru.com/post.json",
            "apiType": "moebooru",
            "description": "Animation sakuga clips | Video-focused",
            "tagSearchTemplate": "https://www.sakugabooru.com/tag.json?order=count&limit=10&name={{query}}*"
        },
        "danbooru": {
            "name": "Danbooru",
            "url": "https://danbooru.donmai.us",
            "api": "https://danbooru.donmai.us/posts.json",
            "apiType": "danbooru",
            "description": "The popular one | Best quantity, quality varies",
            "mirrors": {
                "danbooru.donmai.us": {
                    "url": "https://danbooru.donmai.us",
                    "api": "https://danbooru.donmai.us/posts.json",
                    "tagApi": "https://danbooru.donmai.us/tags.json",
                    "description": "Main site",
                    "sfwOnly": false
                },
                "safebooru.donmai.us": {
                    "url": "https://safebooru.donmai.us",
                    "api": "https://safebooru.donmai.us/posts.json",
                    "tagApi": "https://safebooru.donmai.us/tags.json",
                    "description": "SFW-only",
                    "sfwOnly": true
                }
            },
            "tagSearchTemplate": "https://danbooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*"
        },
        "gelbooru": {
            "name": "Gelbooru",
            "url": "https://gelbooru.com",
            "api": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooru",
            "description": "Great quantity, lots of NSFW, quality varies",
            "tagSearchTemplate": "https://gelbooru.com/index.php?page=dapi&s=tag&q=index&json=1&orderby=count&limit=10&name_pattern={{query}}%"
        },
        "waifu.im": {
            "name": "waifu.im",
            "url": "https://waifu.im",
            "api": "https://api.waifu.im/search",
            "apiType": "waifuIm",
            "description": "Waifus only | Excellent quality, limited quantity",
            "tagSearchTemplate": "https://api.waifu.im/tags"
        },
        "safebooru": {
            "name": "Safebooru",
            "url": "https://safebooru.org",
            "api": "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooru",
            "description": "SFW only | Family-friendly anime images",
            "tagSearchTemplate": "https://safebooru.org/autocomplete.php?q={{query}}",
            // Autocomplete format: {label: "tag (count)", value: "tag"}
            "tagMapFunc": function(response) {
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
        },
        "rule34": {
            "name": "Rule34",
            "url": "https://rule34.xxx",
            "api": "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "NSFW | Requires API key (rule34.xxx/account)",
            "tagSearchTemplate": "https://api.rule34.xxx/autocomplete.php?q={{query}}",
            // Autocomplete format: {label: "tag (count)", value: "tag"}
            "tagMapFunc": function(response) {
                if (!response || !Array.isArray(response)) return []
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var count = 0
                    if (item && item.label) {
                        var match = item.label.match(/\((\d+)\)/)
                        if (match && match[1]) count = parseInt(match[1])
                    }
                    result.push({ name: item.value || "", count: count })
                }
                return result
            }
        },
        "e621": {
            "name": "e621",
            "url": "https://e621.net",
            "api": "https://e621.net/posts.json",
            "apiType": "e621",
            "description": "Furry artwork | NSFW, requires User-Agent",
            "mirrors": {
                "e621.net": {
                    "url": "https://e621.net",
                    "api": "https://e621.net/posts.json",
                    "tagApi": "https://e621.net/tags.json",
                    "description": "Main site (NSFW)",
                    "sfwOnly": false
                },
                "e926.net": {
                    "url": "https://e926.net",
                    "api": "https://e926.net/posts.json",
                    "tagApi": "https://e926.net/tags.json",
                    "description": "SFW-only mirror",
                    "sfwOnly": true
                }
            },
            "tagSearchTemplate": "https://e621.net/tags.json?limit=10&search[name_matches]={{query}}*&search[order]=count"
        },
        "wallhaven": {
            "name": "Wallhaven",
            "url": "https://wallhaven.cc",
            "api": "https://wallhaven.cc/api/v1/search",
            "apiType": "wallhaven",
            "description": "Desktop wallpapers | High quality, all resolutions",
            "tagSearchTemplate": "https://wallhaven.cc/api/v1/search?q={{query}}&sorting=relevance"
        },
        "nekos_best": {
            "name": "nekos.best",
            "url": "https://nekos.best",
            "api": "https://nekos.best/api/v2/neko",
            "apiType": "nekosBest",
            "description": "Anime characters | Random images, high quality"
        },
        "xbooru": {
            "name": "Xbooru",
            "url": "https://xbooru.com",
            "api": "https://xbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "Hentai focused imageboard"
        },
        "tbib": {
            "name": "TBIB",
            "url": "https://tbib.org",
            "api": "https://tbib.org/index.php?page=dapi&s=post&q=index&json=1",
            "description": "The Big ImageBoard | 8M+ images aggregator",
            "mapFunc": (response) => {
                if (!response || !Array.isArray(response)) return []
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item || !item.directory || !item.image) continue
                    var fileUrl = "https://tbib.org/images/" + item.directory + "/" + item.image
                    var previewUrl = "https://tbib.org/thumbnails/" + item.directory + "/thumbnail_" + (item.hash || "") + ".jpg"
                    result.push({
                        "id": item.id,
                        "width": item.width || 0,
                        "height": item.height || 0,
                        "aspect_ratio": (item.width && item.height) ? item.width / item.height : 1,
                        "tags": item.tags || "",
                        "rating": item.rating ? item.rating.charAt(0) : "q",
                        "is_nsfw": (item.rating !== "safe"),
                        "md5": item.hash || "",
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
            "apiType": "shimmie",
            "description": "Rule34 (Shimmie) | 3.5M+ images",
            "isXml": true
        },
        "hypnohub": {
            "name": "Hypnohub",
            "url": "https://hypnohub.net",
            "api": "https://hypnohub.net/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "Hypnosis/mind control themed | ~92k images"
        },
        "aibooru": {
            "name": "AIBooru",
            "url": "https://aibooru.online",
            "api": "https://aibooru.online/posts.json",
            "apiType": "danbooru",
            "description": "AI-generated art | ~150k images",
            "tagSearchTemplate": "https://aibooru.online/tags.json?limit=10&search[name_matches]={{query}}*"
        },
        "zerochan": {
            "name": "Zerochan",
            "url": "https://www.zerochan.net",
            "api": "https://www.zerochan.net",
            "apiType": "zerochan",
            "description": "High-quality anime art | SFW-focused"
            // Note: Zerochan requires User-Agent header, see UrlBuilder
        },
        "sankaku": {
            "name": "Sankaku Channel",
            "url": "https://chan.sankakucomplex.com",
            "api": "https://sankakuapi.com/v2/posts",
            "apiType": "sankaku",
            "description": "Large anime imageboard | Mixed content",
            "tagSearchTemplate": "https://sankakuapi.com/v2/tags?name={{query}}*&limit=10"
        },
        "idol_sankaku": {
            "name": "Idol Sankaku",
            "url": "https://idol.sankakucomplex.com",
            "api": "https://sankakuapi.com/v2/posts",
            "apiType": "sankaku",
            "description": "Japanese idols | Real photos",
            "tagSearchTemplate": "https://sankakuapi.com/v2/tags?name={{query}}*&limit=10"
        },
        "derpibooru": {
            "name": "Derpibooru",
            "url": "https://derpibooru.org",
            "api": "https://derpibooru.org/api/v1/json/search/images",
            "apiType": "philomena",
            "description": "MLP artwork | Philomena engine",
            "tagSearchTemplate": "https://derpibooru.org/api/v1/json/search/tags?q={{query}}*"
        },
        "3dbooru": {
            "name": "3Dbooru",
            "url": "https://behoimi.org",
            "api": "https://behoimi.org/post/index.json",
            "apiType": "moebooru",
            "description": "3D rendered art | Moebooru fork",
            "tagSearchTemplate": "https://behoimi.org/tag/index.json?order=count&limit=10&name={{query}}*"
        },
        "anime_pictures": {
            "name": "Anime-Pictures",
            "url": "https://anime-pictures.net",
            "description": "Curated anime wallpapers | Grabber-only",
            "useGrabberFallback": true
        },
        "e_shuushuu": {
            "name": "E-Shuushuu",
            "url": "https://e-shuushuu.net",
            "description": "Cute anime art | Grabber-only",
            "useGrabberFallback": true
        }
    })

    // =========================================================================
    // Helper Functions (Stateless)
    // =========================================================================

    // Check if provider has mirrors
    function providerHasMirrors(provider) {
        return providers[provider] && providers[provider].mirrors ? true : false
    }

    // Get list of mirror keys for a provider
    function getMirrorList(provider) {
        if (!providerHasMirrors(provider)) return []
        return Object.keys(providers[provider].mirrors)
    }

    // Get sort options for a provider
    function getSortOptionsForProvider(provider) {
        var options = providerSortOptions[provider]
        return options ? options : []
    }

    // Check if provider supports sorting
    function providerSupportsSorting(provider) {
        return getSortOptionsForProvider(provider).length > 0
    }

    // Check if provider supports age filter
    function providerSupportsAgeFilter(provider) {
        return ageFilterProviders.indexOf(provider) !== -1
    }

    // Check if provider is SFW-only
    function isProviderSfwOnly(provider) {
        return sfwOnlyProviders.indexOf(provider) !== -1
    }

    // Check if provider is NSFW-only
    function isProviderNsfwOnly(provider) {
        return nsfwOnlyProviders.indexOf(provider) !== -1
    }

    // Check if provider requires curl
    function providerRequiresCurl(provider) {
        return curlProviders.indexOf(provider) !== -1
    }

    // Get Grabber source name for provider
    function getGrabberSource(provider) {
        return grabberSources[provider] ? grabberSources[provider] : null
    }

    // Check if provider has Grabber support
    function hasGrabberSupport(provider) {
        return grabberSources[provider] ? true : false
    }

    // Get the mapFunc for a provider, using API family mappers when available
    function getProviderMapFunc(providerKey) {
        var provider = providers[providerKey]
        if (!provider) return null
        // Use inline mapFunc if defined (provider override)
        if (provider.mapFunc) return provider.mapFunc
        // Otherwise use API family mapper
        if (provider.apiType && ApiTypes.BooruApiTypes[provider.apiType]) {
            return ApiTypes.BooruApiTypes[provider.apiType].mapFunc
        }
        return null
    }

    // Get the tagMapFunc for a provider
    function getProviderTagMapFunc(providerKey) {
        var provider = providers[providerKey]
        if (!provider) return null
        // Use inline tagMapFunc if defined
        if (provider.tagMapFunc) return provider.tagMapFunc
        // Otherwise use API family mapper
        if (provider.apiType && ApiTypes.BooruApiTypes[provider.apiType]) {
            return ApiTypes.BooruApiTypes[provider.apiType].tagMapFunc
        }
        return null
    }

    // Get the booru post URL for viewing on the site
    function getPostUrl(provider, imageId) {
        var p = providers[provider]
        if (!p || !imageId) return ""

        var baseUrl = p.url
        var apiType = p.apiType || ""

        // URL patterns by API type
        switch (apiType) {
            case "moebooru":
                return baseUrl + "/post/show/" + imageId
            case "danbooru":
                return baseUrl + "/posts/" + imageId
            case "gelbooru":
            case "gelbooruNsfw":
                return baseUrl + "/index.php?page=post&s=view&id=" + imageId
            case "e621":
                return baseUrl + "/posts/" + imageId
            case "wallhaven":
                return baseUrl + "/w/" + imageId
            case "sankaku":
                return baseUrl + "/post/show/" + imageId
            case "shimmie":
                return baseUrl + "/post/view/" + imageId
            case "philomena":
                return baseUrl + "/images/" + imageId
            case "zerochan":
                return baseUrl + "/" + imageId
            default:
                // waifuIm, nekosBest don't have post pages
                return ""
        }
    }

    // Transform source URLs (e.g., pximg.net -> pixiv.net artwork link)
    function getWorkingImageSource(url) {
        if (!url) return null
        if (url.indexOf('pximg.net') >= 0) {
            var filename = url.substring(url.lastIndexOf('/') + 1)
            var artworkId = filename.replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')
            return "https://www.pixiv.net/en/artworks/" + artworkId
        }
        return url
    }

    // =========================================================================
    // Sort Metatag Injection (Deduplication from Booru.qml)
    // =========================================================================

    /**
     * Get the sort metatag prefix for a provider.
     * Returns "order:" for Moebooru/Danbooru/e621/Sankaku, "sort:" for Gelbooru, null for URL param providers.
     */
    function getSortMetatagPrefix(provider) {
        // Moebooru sites use order:X
        if (provider === "yandere" || provider === "konachan" ||
            provider === "sakugabooru" || provider === "3dbooru") {
            return "order:"
        }
        // Danbooru uses order:X
        if (provider === "danbooru" || provider === "aibooru") {
            return "order:"
        }
        // e621 uses order:X
        if (provider === "e621") {
            return "order:"
        }
        // Gelbooru-based sites use sort:X
        if (provider === "gelbooru" || provider === "safebooru" ||
            provider === "rule34" || provider === "xbooru" ||
            provider === "tbib" || provider === "hypnohub") {
            return "sort:"
        }
        // Sankaku sites use order:X
        if (provider === "sankaku" || provider === "idol_sankaku") {
            return "order:"
        }
        // Zerochan, Wallhaven, Derpibooru use URL params (not metatags)
        return null
    }

    /**
     * Inject sort metatag into tag string if provider uses metatag-based sorting.
     * Returns modified tagString with sort prepended, or original if provider uses URL params.
     */
    function injectSortMetatag(provider, tagString, sorting) {
        if (!sorting || sorting.length === 0) return tagString
        var prefix = getSortMetatagPrefix(provider)
        if (!prefix) return tagString
        return prefix + sorting + " " + tagString
    }
}
