import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'relay_pow.dart';

/// Where reports go. Public by necessity — it ships inside the APK — which is
/// why the relay meters every caller rather than trusting this to stay unknown.
const String relayBaseUrl = 'https://relay-bambu.morganmlg.com';

/// A challenge fetched when the report form opens.
///
/// [notBefore] is the whole point: the relay refuses the report until then, and
/// makes each further challenge for this installation due later than the last.
/// Fetching it while the user is still typing is what keeps that invisible —
/// people spend half a minute writing, which is exactly the budget the delay
/// needs.
@immutable
class RelayTicket {
  const RelayTicket({
    required this.ticket,
    required this.notBefore,
    required this.expiresAt,
    required this.challenge,
    this.powNonce,
  });

  final String ticket;
  final DateTime notBefore;
  final DateTime expiresAt;
  final PowChallenge challenge;

  /// The solved proof of work, once somebody has solved it.
  ///
  /// Carried on the ticket so the work happens while the user is still writing
  /// rather than on the send tap: it is about a second of SHA-256, and a second
  /// between "send" and anything moving reads as the app having hung. Null means
  /// nobody has solved it yet, and the sender falls back to solving in place —
  /// which is what happens to a report queued before the app was killed.
  final String? powNonce;

  RelayTicket solved(String nonce) => RelayTicket(
        ticket: ticket,
        notBefore: notBefore,
        expiresAt: expiresAt,
        challenge: challenge,
        powNonce: nonce,
      );

  bool get ready => !DateTime.now().isBefore(notBefore);
  bool get expired => DateTime.now().isAfter(expiresAt);
  Duration get wait {
    final left = notBefore.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, dynamic> toJson() => {
        'ticket': ticket,
        'notBefore': notBefore.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'seed': challenge.seed,
        'bits': challenge.bits,
        if (powNonce != null) 'powNonce': powNonce,
      };

  static RelayTicket fromJson(Map<String, dynamic> json) => RelayTicket(
        ticket: json['ticket'] as String,
        notBefore:
            DateTime.fromMillisecondsSinceEpoch(json['notBefore'] as int),
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
        challenge: PowChallenge(
          seed: json['seed'] as String,
          bits: json['bits'] as int,
        ),
        powNonce: json['powNonce'] as String?,
      );
}

/// Why a send did not produce an issue. The distinction the UI cares about is
/// [retryable]: everything else is a dead end the user has to be told about.
enum RelayFailure {
  /// Too early, or the relay is shut. Worth queuing and trying again.
  notYet,

  /// The relay has stopped issuing challenges for this installation, or the
  /// global breaker is down. Retrying soon will not help.
  refused,

  /// Already reported. Nothing to retry.
  duplicate,

  /// Network, or the relay itself is unreachable.
  unreachable,

  /// The relay rejected the envelope. A bug on this side; retrying is pointless.
  rejected,

  /// Demo mode. The only value here the relay never produces: the app refuses
  /// to publish on its behalf and never calls out at all, so it is reported the
  /// same way as any other reason no issue exists.
  demo,
}

class RelayException implements Exception {
  const RelayException(this.failure, {this.retryAfter});

  final RelayFailure failure;
  final Duration? retryAfter;

  bool get retryable =>
      failure == RelayFailure.notYet || failure == RelayFailure.unreachable;
}

/// Talks to the report relay. Two calls: one when the form opens, one to send.
class RelayClient {
  RelayClient(this._dio, {this.baseUrl = relayBaseUrl});

  final Dio _dio;
  final String baseUrl;

  Future<RelayTicket> challenge(String installId) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$baseUrl/challenge',
        data: {'installId': installId},
        options: Options(
          contentType: Headers.jsonContentType,
          // Everything but 2xx is handled below rather than thrown, so the
          // failure reasons stay in one place.
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (_) {
      throw const RelayException(RelayFailure.unreachable);
    }

    if (response.statusCode == 503) {
      throw RelayException(
        RelayFailure.refused,
        retryAfter: _retryAfter(response),
      );
    }
    if (response.statusCode != 200) {
      throw const RelayException(RelayFailure.rejected);
    }

    final body = (response.data as Map).cast<String, dynamic>();
    return RelayTicket(
      ticket: body['ticket'] as String,
      notBefore: DateTime.fromMillisecondsSinceEpoch(body['nbf'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(body['exp'] as int),
      challenge: PowChallenge(
        seed: body['seed'] as String,
        bits: body['bits'] as int,
      ),
    );
  }

  /// Sends one report and returns the issue URL.
  ///
  /// The log is gzipped and base64-encoded here rather than on the relay: the
  /// phone has the file already, compression costs more than decompression, and
  /// it keeps the relay's cost independent of how long the recording was.
  Future<String> send({
    required String installId,
    required RelayTicket ticket,
    required String description,
    required Map<String, Object> header,
    required int logSchema,
    required String log,
  }) async {
    // Normally already solved while the user was writing; solving here is the
    // fallback for a report that outlived the process that queued it.
    final powNonce = ticket.powNonce ?? await solvePow(ticket.challenge);
    final logGz = base64Encode(gzip.encode(utf8.encode(log)));

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$baseUrl/report',
        data: {
          'installId': installId,
          'header': header,
          'description': description,
          'logSchema': logSchema,
          'logGz': logGz,
          'ticket': ticket.ticket,
          'powNonce': powNonce,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (_) {
      throw const RelayException(RelayFailure.unreachable);
    }

    switch (response.statusCode) {
      case 201:
        return ((response.data as Map).cast<String, dynamic>()['url']) as String;
      case 403:
        // The ticket was not usable yet, or no longer. Both are worth waiting
        // out with a fresh challenge rather than reporting as a failure.
        throw const RelayException(RelayFailure.notYet);
      case 409:
        throw const RelayException(RelayFailure.duplicate);
      case 503:
        throw RelayException(
          RelayFailure.notYet,
          retryAfter: _retryAfter(response),
        );
      case 502:
        throw const RelayException(RelayFailure.unreachable);
      default:
        throw const RelayException(RelayFailure.rejected);
    }
  }

  Duration? _retryAfter(Response<dynamic> response) {
    final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
