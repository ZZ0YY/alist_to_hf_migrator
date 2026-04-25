/// Utility class providing path-encoding and path-manipulation helpers used
/// throughout the migration pipeline.
class PathEncoder {
  PathEncoder._(); // prevent instantiation

  // --------------------------------------------------------------------------
  // Encoding helpers
  // --------------------------------------------------------------------------

  /// Full URL-encoding suitable for the Alist `File-Path` header.
  ///
  /// Unlike [urlEncodeQuery], this encodes **every special character**,
  /// including forward slashes `/` → `%2F`, because the entire remote path
  /// is placed into a single HTTP header value.
  ///
  /// Example: `/阿里云盘/images/photo.jpg`
  ///       → `%2F%E9%98%BF%E9%87%8C%E4%BA%91%E7%9B%98%2Fimages%2Fphoto.jpg`
  static String encodeFilePath(String path) {
    return Uri.encodeComponent(path);
  }

  /// Standard URL encoding for query-parameter values.
  ///
  /// Encodes spaces, CJK characters, and other reserved characters but
  /// preserves forward slashes `/` and colons `:` so that path-like values
  /// remain readable in query strings.
  ///
  /// Example: `/阿里云盘/images` → `%2F%E9%98%BF%E9%87%8C%E4%BA%91%E7%9B%98%2Fimages`
  ///
  /// Note: [Uri.encodeComponent] already encodes `/` for header use. For
  /// query params that must keep `/` as-is, we decode those back.
  static String urlEncodeQuery(String value) {
    // Encode fully first, then restore '/' to keep paths readable.
    return Uri.encodeComponent(value).replaceAll('%2F', '/');
  }

  // --------------------------------------------------------------------------
  // Path manipulation helpers
  // --------------------------------------------------------------------------

  /// Extract the parent directory from [fullPath].
  ///
  /// ```
  /// extractParentPath('/dir/subdir/file.jpg') → '/dir/subdir'
  /// extractParentPath('/file.jpg')            → '/'
  /// extractParentPath('/')                     → '/'
  /// ```
  static String extractParentPath(String fullPath) {
    final normalized = _normalizePath(fullPath);
    if (normalized == '/') return '/';
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return normalized.substring(0, lastSlash);
  }

  /// Extract the file (or folder) name from [fullPath].
  ///
  /// ```
  /// extractFileName('/dir/subdir/file.jpg') → 'file.jpg'
  /// extractFileName('/dir/')                → 'dir'
  /// extractFileName('/')                    → ''
  /// ```
  static String extractFileName(String fullPath) {
    final normalized = _normalizePath(fullPath);
    if (normalized == '/') return '';
    final lastSlash = normalized.lastIndexOf('/');
    return normalized.substring(lastSlash + 1);
  }

  /// Remove an Alist mount prefix from a full remote path so that the
  /// remaining relative path can be used as an `uploadFolder` on
  /// HuggingFace.
  ///
  /// Example:
  /// ```
  /// stripMountPrefix('/阿里云盘/images/photo.jpg', '/阿里云盘')
  ///   → 'images/photo.jpg'
  ///
  /// stripMountPrefix('/阿里云盘/file.txt', '/阿里云盘')
  ///   → 'file.txt'
  /// ```
  ///
  /// Leading `/` on the result is stripped. If [fullPath] does not start
  /// with [mountPath], the original [fullPath] (minus leading `/`) is
  /// returned.
  static String stripMountPrefix(String fullPath, String mountPath) {
    final normalizedFull = _normalizePath(fullPath);
    final normalizedMount = _normalizePath(mountPath);

    if (!normalizedFull.startsWith(normalizedMount)) {
      // Mount prefix doesn't match — return the path without leading '/'.
      return normalizedFull.startsWith('/')
          ? normalizedFull.substring(1)
          : normalizedFull;
    }

    final remainder =
        normalizedFull.substring(normalizedMount.length);
    // Strip leading '/' from the remainder.
    if (remainder.startsWith('/')) {
      return remainder.substring(1);
    }
    return remainder;
  }

  // --------------------------------------------------------------------------
  // Internal
  // --------------------------------------------------------------------------
  static String _normalizePath(String path) {
    // Collapse multiple slashes into one and remove trailing slash (except root).
    String result = path.replaceAll(RegExp(r'/+'), '/');
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
