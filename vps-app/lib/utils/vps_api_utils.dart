// PublicNode VPS
// Copyright (C) 2026 mohammadhasanulislam
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

class VpsApiUtils {
  /// Robustly constructs a Uri for the VPS API from a potentially malformed base URL.
  /// Handles wss://, ws://, https://, http:' '//, and raw hostnames.
  static Uri buildUri(
    String baseUrl,
    String endpoint, [
    Map<String, String>? queryParams,
  ]) {
    final trimmedBase = baseUrl.trim();
    if (trimmedBase.isEmpty) throw Exception('Base URL is empty');

    // 1. Determine protocol and clean the base
    final bool isSecure =
        trimmedBase.startsWith('wss://') || trimmedBase.startsWith('https://');

    String cleanBase = trimmedBase
        .replaceFirst('wss://', '')
        .replaceFirst('ws://', '')
        .replaceFirst('https://', '')
        .replaceFirst('http:' '//', '')
        .split('/')
        .first;

    if (cleanBase.isEmpty) throw Exception('Invalid host in base URL');

    // 2. Split host and port
    final hostParts = cleanBase.split(':');
    final host = hostParts[0];
    final int? port = hostParts.length > 1 ? int.tryParse(hostParts[1]) : null;

    // 3. Construct final URI
    final String authority = port != null ? '$host:$port' : host;
    final String path = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    if (isSecure) {
      return Uri.https(authority, path, queryParams);
    } else {
      return Uri.http(authority, path, queryParams);
    }
  }
}
