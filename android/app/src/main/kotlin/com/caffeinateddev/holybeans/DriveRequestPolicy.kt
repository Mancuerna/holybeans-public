package com.caffeinateddev.holybeans

import java.net.URL

internal object DriveRequestPolicy {
    fun url(address: String): URL {
        val url = URL(address)
        require(url.protocol == "https" && url.host == "www.googleapis.com" &&
            url.port == -1 && url.userInfo == null && url.ref == null &&
            (url.path.startsWith("/drive/v3/") || url.path.startsWith("/upload/drive/v3/")))
        require(!url.path.contains('\\') &&
            !Regex("%2f|%5c|%25", RegexOption.IGNORE_CASE).containsMatchIn(url.path))
        require(url.toURI().path.split('/').none { it == "." || it == ".." })
        return url
    }
}
