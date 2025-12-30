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
    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)
    signal responseFinished()

    property string failMessage: "That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number"
    property var responses: []
    property int runningRequests: 0
    property bool replaceOnNextResponse: false  // When true, replace responses instead of appending
    property string defaultUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: Object.keys(providers).filter(provider => provider !== "system" && providers[provider].api)

    // Persistent state
    property string currentProvider: "yandere"
    property bool allowNsfw: false
    property int limit: 20

    // Gelbooru API credentials (configured in config.json under "booru")
    // Get your key at: https://gelbooru.com/index.php?page=account&s=options
    property string gelbooruApiKey: ConfigOptions.booru?.gelbooruApiKey ?? ""
    property string gelbooruUserId: ConfigOptions.booru?.gelbooruUserId ?? ""

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
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
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
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
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
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.file_url ?? item.large_file_url,
                        "file_url": item.large_file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
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
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
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
                        "preview_url": item.sample_url ?? item.url,
                        "sample_url": item.url,
                        "file_url": item.url,
                        "file_ext": item.extension,
                        "source": getWorkingImageSource(item.source) ?? item.url,
                    }
                })
            },
            "tagSearchTemplate": "https://api.waifu.im/tags",
            "tagMapFunc": (response) => {
                return [...response.versatile.map(item => ({name: item})),
                    ...response.nsfw.map(item => ({name: item}))]
            }
        }
    }

    function getWorkingImageSource(url) {
        if (!url) return null;
        if (url.includes('pximg.net')) {
            return `https://www.pixiv.net/en/artworks/${url.substring(url.lastIndexOf('/') + 1).replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')}`;
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
            root.addSystemMessage(msg)
        } else {
            root.addSystemMessage("Invalid API provider. Supported:\n- " + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        responses = []
    }

    function addSystemMessage(message) {
        responses = [...responses, root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": message
        })]
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1) {
        var provider = providers[currentProvider]
        var baseUrl = provider.api
        var url = baseUrl
        var tagString = tags.join(" ")

        if (!nsfw && currentProvider !== "waifu.im") {
            if (currentProvider == "gelbooru")
                tagString += " rating:general";
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
        } else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            if (currentProvider == "gelbooru") {
                params.push("pid=" + page)
                // Gelbooru requires API key authentication
                if (gelbooruApiKey && gelbooruUserId) {
                    params.push("api_key=" + gelbooruApiKey)
                    params.push("user_id=" + gelbooruUserId)
                }
            } else {
                params.push("page=" + page)
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
        var url = constructRequestUrl(tags, nsfw, limit, page)
        console.log("[Booru] Making request to " + url)

        const newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": currentProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    const provider = providers[currentProvider]
                    let response = JSON.parse(xhr.responseText)
                    response = provider.mapFunc(response)
                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                    newResponse.message = root.failMessage
                } finally {
                    root.runningRequests--;
                    if (root.replaceOnNextResponse) {
                        root.responses = [newResponse]
                        root.replaceOnNextResponse = false
                    } else {
                        root.responses = [...root.responses, newResponse]
                    }
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
                newResponse.message = root.failMessage
                root.runningRequests--;
                if (root.replaceOnNextResponse) {
                    root.responses = [newResponse]
                    root.replaceOnNextResponse = false
                } else {
                    root.responses = [...root.responses, newResponse]
                }
            }
            root.responseFinished()
        }

        try {
            if (currentProvider == "danbooru") {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            root.runningRequests++;
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        }
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (!provider.tagSearchTemplate) return

        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        // Add Gelbooru API credentials for tag search
        if (currentProvider === "gelbooru" && gelbooruApiKey && gelbooruUserId) {
            url += "&api_key=" + gelbooruApiKey + "&user_id=" + gelbooruUserId
        }

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
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
            }
        }

        try {
            if (currentProvider == "danbooru") {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        }
    }
}
