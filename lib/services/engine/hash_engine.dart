import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Result of hashing a local file.
///
/// Contains the full SHA-256 digest and a small sample for dedup preview.
class HashResult {
  /// SHA-256 hash of the entire file, as a lowercase hex string (64 chars).
  final String sha256;

  /// Base64-encoded first 512 bytes of the file (for quick fingerprinting).
  final String fileSample;

  const HashResult({required this.sha256, required this.fileSample});
}

/// Stateless engine for computing cryptographic hashes of local files.
///
/// The file **must be fully downloaded** before hashing begins. This
/// post-download approach guarantees hash accuracy regardless of network
/// interruptions.
///
/// For a typical ~1 GB file on an SSD, hashing takes approximately 3 seconds.
class HashEngine {
  /// Size of the file prefix sampled for [HashResult.fileSample].
  static const int _sampleSize = 512;

  /// Read buffer size for the streaming SHA-256 computation.
  static const int _chunkSize = 64 * 1024; // 64 KB

  /// Compute SHA-256 hash and a file sample for a fully downloaded file.
  ///
  /// Reads the file from disk (NOT streaming during download) to ensure
  /// hash accuracy for large files.
  ///
  /// [filePath] must point to an existing, fully written file.
  ///
  /// Returns a [HashResult] containing the hex SHA-256 digest and a base64
  /// sample of the first 512 bytes.
  ///
  /// Throws [FileSystemException] if the file does not exist or cannot be
  /// opened, or [PathNotFoundException] if the path is invalid.
  Future<HashResult> computeHash(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw FileSystemException(
        'File does not exist: $filePath',
        filePath,
      );
    }

    // Open as random-access so we can seek back after reading the sample.
    final raf = await file.open(mode: FileMode.read);

    try {
      // ── 1. Read first 512 bytes as the file sample ─────────────────────
      final sampleBytes = <int>[];
      final fileLength = await raf.length();
      final bytesToSample = fileLength < _sampleSize ? fileLength : _sampleSize;

      for (int i = 0; i < bytesToSample; i++) {
        final byte = await raf.readByte();
        sampleBytes.add(byte);
      }
      final fileSample = base64Encode(Uint8List.fromList(sampleBytes));

      // ── 2. Reset position to start of file for hashing ─────────────────
      await raf.setPosition(0);

      // ── 3. Stream the entire file through SHA-256 ──────────────────────
      var output = AccumulatorSink<Digest>();
      var input = sha256.startChunkedConversion(output);

      final buffer = Uint8List(_chunkSize);
      int bytesRead;

      do {
        bytesRead = await raf.readInto(buffer);
        if (bytesRead > 0) {
          input.add(buffer.sublist(0, bytesRead));
        }
      } while (bytesRead == _chunkSize);

      // Finalize the hash.
      input.close();
      final digest = output.events.single;

      return HashResult(
        sha256: digest.toString(),
        fileSample: fileSample,
      );
    } finally {
      await raf.close();
    }
  }
}
