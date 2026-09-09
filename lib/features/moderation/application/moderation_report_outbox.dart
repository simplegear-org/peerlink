abstract interface class ModerationReportOutbox {
  List<Map<String, dynamic>> read();

  Future<void> write(List<Map<String, dynamic>> reports);
}
