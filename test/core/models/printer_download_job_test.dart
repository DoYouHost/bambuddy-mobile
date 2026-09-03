import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrinterDownloadJob.fromJson', () {
    test('reads a ready job whole', () {
      final job = PrinterDownloadJob.fromJson(const {
        'job_id': 'abc',
        'printer_id': 3,
        'state': 'ready',
        'requested': 7,
        'successful': 7,
        'failed': 0,
        'token': 'tok',
        'filename': 'X1-files.zip',
        'message': null,
      });

      expect(job.jobId, 'abc');
      expect(job.printerId, 3);
      expect(job.state, PrinterDownloadJobState.ready);
      expect(job.token, 'tok');
      expect(job.filename, 'X1-files.zip');
      expect(job.isComplete, isTrue);
      expect(job.state.isTerminal, isTrue);
    });

    test('a state this app does not know is not a finished download', () {
      final job = PrinterDownloadJob.fromJson(const {
        'job_id': 'abc',
        'printer_id': 1,
        'state': 'compressing',
        'requested': 2,
      });

      expect(job.state, PrinterDownloadJobState.unknown);
      // The whole point of the fallback: polling must keep going rather than
      // treat an unfamiliar phase as a bundle waiting to be fetched.
      expect(job.state.isTerminal, isFalse);
    });

    test('an empty body parses instead of throwing', () {
      final job = PrinterDownloadJob.fromJson(const {});

      expect(job.jobId, '');
      expect(job.state, PrinterDownloadJobState.unknown);
      expect(job.requested, 0);
      expect(job.token, isNull);
      expect(job.progress, isNull);
    });

    test('a failed job keeps the server\'s sentence', () {
      final job = PrinterDownloadJob.fromJson(const {
        'job_id': 'abc',
        'printer_id': 1,
        'state': 'failed',
        'requested': 3,
        'message': 'Printer download preparation exceeded the 30-minute limit',
      });

      expect(job.state, PrinterDownloadJobState.failed);
      expect(job.message, contains('30-minute'));
    });

    test('a bundle short of the selection is not complete', () {
      final job = PrinterDownloadJob.fromJson(const {
        'job_id': 'abc',
        'printer_id': 1,
        'state': 'ready',
        'requested': 5,
        'successful': 4,
        'failed': 1,
        'token': 'tok',
      });

      expect(job.isComplete, isFalse);
      expect(job.failed, 1);
    });
  });

  group('progress', () {
    test('null until something has been staged, so the bar stays honest', () {
      final job = PrinterDownloadJob.fromJson(const {
        'state': 'preparing',
        'requested': 4,
        'successful': 0,
        'failed': 0,
      });

      expect(job.progress, isNull);
    });

    test('counts a file the server could not read as dealt with', () {
      final job = PrinterDownloadJob.fromJson(const {
        'state': 'preparing',
        'requested': 4,
        'successful': 1,
        'failed': 1,
      });

      // 2 of 4 are behind us — a bar that ignored the failure would sit at 25%
      // while the server had moved on.
      expect(job.progress, 0.5);
    });

    test('never reports more than done', () {
      final job = PrinterDownloadJob.fromJson(const {
        'state': 'ready',
        'requested': 2,
        'successful': 3,
        'failed': 1,
      });

      expect(job.progress, 1.0);
    });

    test('a job with nothing requested has no fraction to give', () {
      final job = PrinterDownloadJob.fromJson(const {
        'state': 'preparing',
        'requested': 0,
        'successful': 0,
      });

      expect(job.progress, isNull);
    });
  });
}
