class Pagination {
  final int? totalResult;
  final int? startPage;
  final int? itemsPerPage;
  final int? itemsOnPage;

  Pagination({
    this.totalResult,
    this.startPage,
    this.itemsPerPage,
    this.itemsOnPage,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      totalResult: json['totalResult'] as int?,
      startPage: json['startPage'] as int?,
      itemsPerPage: json['itemsPerPage'] as int?,
      itemsOnPage: json['itemsOnPage'] as int?,
    );
  }
}