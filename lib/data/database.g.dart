// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastChapterMeta = const VerificationMeta(
    'lastChapter',
  );
  @override
  late final GeneratedColumn<int> lastChapter = GeneratedColumn<int>(
    'last_chapter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastParagraphMeta = const VerificationMeta(
    'lastParagraph',
  );
  @override
  late final GeneratedColumn<int> lastParagraph = GeneratedColumn<int>(
    'last_paragraph',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loreMeta = const VerificationMeta('lore');
  @override
  late final GeneratedColumn<String> lore = GeneratedColumn<String>(
    'lore',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    format,
    sourcePath,
    createdAt,
    lastChapter,
    lastParagraph,
    lore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_chapter')) {
      context.handle(
        _lastChapterMeta,
        lastChapter.isAcceptableOrUnknown(
          data['last_chapter']!,
          _lastChapterMeta,
        ),
      );
    }
    if (data.containsKey('last_paragraph')) {
      context.handle(
        _lastParagraphMeta,
        lastParagraph.isAcceptableOrUnknown(
          data['last_paragraph']!,
          _lastParagraphMeta,
        ),
      );
    }
    if (data.containsKey('lore')) {
      context.handle(
        _loreMeta,
        lore.isAcceptableOrUnknown(data['lore']!, _loreMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_chapter'],
      )!,
      lastParagraph: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_paragraph'],
      )!,
      lore: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lore'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  final int id;
  final String title;
  final String author;
  final String format;
  final String sourcePath;
  final DateTime createdAt;
  final int lastChapter;
  final int lastParagraph;
  final String lore;
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.sourcePath,
    required this.createdAt,
    required this.lastChapter,
    required this.lastParagraph,
    required this.lore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['author'] = Variable<String>(author);
    map['format'] = Variable<String>(format);
    map['source_path'] = Variable<String>(sourcePath);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_chapter'] = Variable<int>(lastChapter);
    map['last_paragraph'] = Variable<int>(lastParagraph);
    map['lore'] = Variable<String>(lore);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: Value(author),
      format: Value(format),
      sourcePath: Value(sourcePath),
      createdAt: Value(createdAt),
      lastChapter: Value(lastChapter),
      lastParagraph: Value(lastParagraph),
      lore: Value(lore),
    );
  }

  factory Book.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String>(json['author']),
      format: serializer.fromJson<String>(json['format']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastChapter: serializer.fromJson<int>(json['lastChapter']),
      lastParagraph: serializer.fromJson<int>(json['lastParagraph']),
      lore: serializer.fromJson<String>(json['lore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String>(author),
      'format': serializer.toJson<String>(format),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastChapter': serializer.toJson<int>(lastChapter),
      'lastParagraph': serializer.toJson<int>(lastParagraph),
      'lore': serializer.toJson<String>(lore),
    };
  }

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? format,
    String? sourcePath,
    DateTime? createdAt,
    int? lastChapter,
    int? lastParagraph,
    String? lore,
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author ?? this.author,
    format: format ?? this.format,
    sourcePath: sourcePath ?? this.sourcePath,
    createdAt: createdAt ?? this.createdAt,
    lastChapter: lastChapter ?? this.lastChapter,
    lastParagraph: lastParagraph ?? this.lastParagraph,
    lore: lore ?? this.lore,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      format: data.format.present ? data.format.value : this.format,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastChapter: data.lastChapter.present
          ? data.lastChapter.value
          : this.lastChapter,
      lastParagraph: data.lastParagraph.present
          ? data.lastParagraph.value
          : this.lastParagraph,
      lore: data.lore.present ? data.lore.value : this.lore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('format: $format, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastChapter: $lastChapter, ')
          ..write('lastParagraph: $lastParagraph, ')
          ..write('lore: $lore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    format,
    sourcePath,
    createdAt,
    lastChapter,
    lastParagraph,
    lore,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.format == this.format &&
          other.sourcePath == this.sourcePath &&
          other.createdAt == this.createdAt &&
          other.lastChapter == this.lastChapter &&
          other.lastParagraph == this.lastParagraph &&
          other.lore == this.lore);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> author;
  final Value<String> format;
  final Value<String> sourcePath;
  final Value<DateTime> createdAt;
  final Value<int> lastChapter;
  final Value<int> lastParagraph;
  final Value<String> lore;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.format = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastChapter = const Value.absent(),
    this.lastParagraph = const Value.absent(),
    this.lore = const Value.absent(),
  });
  BooksCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.author = const Value.absent(),
    required String format,
    this.sourcePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastChapter = const Value.absent(),
    this.lastParagraph = const Value.absent(),
    this.lore = const Value.absent(),
  }) : title = Value(title),
       format = Value(format);
  static Insertable<Book> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? format,
    Expression<String>? sourcePath,
    Expression<DateTime>? createdAt,
    Expression<int>? lastChapter,
    Expression<int>? lastParagraph,
    Expression<String>? lore,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (format != null) 'format': format,
      if (sourcePath != null) 'source_path': sourcePath,
      if (createdAt != null) 'created_at': createdAt,
      if (lastChapter != null) 'last_chapter': lastChapter,
      if (lastParagraph != null) 'last_paragraph': lastParagraph,
      if (lore != null) 'lore': lore,
    });
  }

  BooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? author,
    Value<String>? format,
    Value<String>? sourcePath,
    Value<DateTime>? createdAt,
    Value<int>? lastChapter,
    Value<int>? lastParagraph,
    Value<String>? lore,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format ?? this.format,
      sourcePath: sourcePath ?? this.sourcePath,
      createdAt: createdAt ?? this.createdAt,
      lastChapter: lastChapter ?? this.lastChapter,
      lastParagraph: lastParagraph ?? this.lastParagraph,
      lore: lore ?? this.lore,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastChapter.present) {
      map['last_chapter'] = Variable<int>(lastChapter.value);
    }
    if (lastParagraph.present) {
      map['last_paragraph'] = Variable<int>(lastParagraph.value);
    }
    if (lore.present) {
      map['lore'] = Variable<String>(lore.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('format: $format, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastChapter: $lastChapter, ')
          ..write('lastParagraph: $lastParagraph, ')
          ..write('lore: $lore')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters with TableInfo<$ChaptersTable, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _idxMeta = const VerificationMeta('idx');
  @override
  late final GeneratedColumn<int> idx = GeneratedColumn<int>(
    'idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, bookId, idx, title, content];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chapter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('idx')) {
      context.handle(
        _idxMeta,
        idx.isAcceptableOrUnknown(data['idx']!, _idxMeta),
      );
    } else if (isInserting) {
      context.missing(_idxMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      idx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idx'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final int id;
  final int bookId;
  final int idx;
  final String title;
  final String content;
  const Chapter({
    required this.id,
    required this.bookId,
    required this.idx,
    required this.title,
    required this.content,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['idx'] = Variable<int>(idx);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      bookId: Value(bookId),
      idx: Value(idx),
      title: Value(title),
      content: Value(content),
    );
  }

  factory Chapter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      idx: serializer.fromJson<int>(json['idx']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'idx': serializer.toJson<int>(idx),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
    };
  }

  Chapter copyWith({
    int? id,
    int? bookId,
    int? idx,
    String? title,
    String? content,
  }) => Chapter(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    idx: idx ?? this.idx,
    title: title ?? this.title,
    content: content ?? this.content,
  );
  Chapter copyWithCompanion(ChaptersCompanion data) {
    return Chapter(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      idx: data.idx.present ? data.idx.value : this.idx,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('idx: $idx, ')
          ..write('title: $title, ')
          ..write('content: $content')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, bookId, idx, title, content);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.idx == this.idx &&
          other.title == this.title &&
          other.content == this.content);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> idx;
  final Value<String> title;
  final Value<String> content;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.idx = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
  });
  ChaptersCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required int idx,
    required String title,
    required String content,
  }) : bookId = Value(bookId),
       idx = Value(idx),
       title = Value(title),
       content = Value(content);
  static Insertable<Chapter> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? idx,
    Expression<String>? title,
    Expression<String>? content,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (idx != null) 'idx': idx,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
    });
  }

  ChaptersCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? idx,
    Value<String>? title,
    Value<String>? content,
  }) {
    return ChaptersCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      idx: idx ?? this.idx,
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (idx.present) {
      map['idx'] = Variable<int>(idx.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('idx: $idx, ')
          ..write('title: $title, ')
          ..write('content: $content')
          ..write(')'))
        .toString();
  }
}

class $IllustrationsTable extends Illustrations
    with TableInfo<$IllustrationsTable, Illustration> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IllustrationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<int> chapterId = GeneratedColumn<int>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _afterParagraphMeta = const VerificationMeta(
    'afterParagraph',
  );
  @override
  late final GeneratedColumn<int> afterParagraph = GeneratedColumn<int>(
    'after_paragraph',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anchorOffsetMeta = const VerificationMeta(
    'anchorOffset',
  );
  @override
  late final GeneratedColumn<int> anchorOffset = GeneratedColumn<int>(
    'anchor_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _anchorHashMeta = const VerificationMeta(
    'anchorHash',
  );
  @override
  late final GeneratedColumn<String> anchorHash = GeneratedColumn<String>(
    'anchor_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _imgWidthMeta = const VerificationMeta(
    'imgWidth',
  );
  @override
  late final GeneratedColumn<int> imgWidth = GeneratedColumn<int>(
    'img_width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1280),
  );
  static const VerificationMeta _imgHeightMeta = const VerificationMeta(
    'imgHeight',
  );
  @override
  late final GeneratedColumn<int> imgHeight = GeneratedColumn<int>(
    'img_height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(720),
  );
  static const VerificationMeta _historyMeta = const VerificationMeta(
    'history',
  );
  @override
  late final GeneratedColumn<String> history = GeneratedColumn<String>(
    'history',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    chapterId,
    afterParagraph,
    anchorOffset,
    anchorHash,
    prompt,
    imagePath,
    status,
    error,
    imgWidth,
    imgHeight,
    history,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'illustrations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Illustration> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('after_paragraph')) {
      context.handle(
        _afterParagraphMeta,
        afterParagraph.isAcceptableOrUnknown(
          data['after_paragraph']!,
          _afterParagraphMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_afterParagraphMeta);
    }
    if (data.containsKey('anchor_offset')) {
      context.handle(
        _anchorOffsetMeta,
        anchorOffset.isAcceptableOrUnknown(
          data['anchor_offset']!,
          _anchorOffsetMeta,
        ),
      );
    }
    if (data.containsKey('anchor_hash')) {
      context.handle(
        _anchorHashMeta,
        anchorHash.isAcceptableOrUnknown(data['anchor_hash']!, _anchorHashMeta),
      );
    } else if (isInserting) {
      context.missing(_anchorHashMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('img_width')) {
      context.handle(
        _imgWidthMeta,
        imgWidth.isAcceptableOrUnknown(data['img_width']!, _imgWidthMeta),
      );
    }
    if (data.containsKey('img_height')) {
      context.handle(
        _imgHeightMeta,
        imgHeight.isAcceptableOrUnknown(data['img_height']!, _imgHeightMeta),
      );
    }
    if (data.containsKey('history')) {
      context.handle(
        _historyMeta,
        history.isAcceptableOrUnknown(data['history']!, _historyMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Illustration map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Illustration(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_id'],
      )!,
      afterParagraph: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}after_paragraph'],
      )!,
      anchorOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anchor_offset'],
      )!,
      anchorHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor_hash'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      )!,
      imgWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}img_width'],
      )!,
      imgHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}img_height'],
      )!,
      history: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}history'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $IllustrationsTable createAlias(String alias) {
    return $IllustrationsTable(attachedDatabase, alias);
  }
}

class Illustration extends DataClass implements Insertable<Illustration> {
  final int id;
  final int bookId;
  final int chapterId;
  final int afterParagraph;
  final int anchorOffset;
  final String anchorHash;
  final String prompt;
  final String? imagePath;
  final String status;
  final String error;
  final int imgWidth;
  final int imgHeight;
  final String history;
  final DateTime createdAt;
  const Illustration({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.afterParagraph,
    required this.anchorOffset,
    required this.anchorHash,
    required this.prompt,
    this.imagePath,
    required this.status,
    required this.error,
    required this.imgWidth,
    required this.imgHeight,
    required this.history,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['chapter_id'] = Variable<int>(chapterId);
    map['after_paragraph'] = Variable<int>(afterParagraph);
    map['anchor_offset'] = Variable<int>(anchorOffset);
    map['anchor_hash'] = Variable<String>(anchorHash);
    map['prompt'] = Variable<String>(prompt);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['status'] = Variable<String>(status);
    map['error'] = Variable<String>(error);
    map['img_width'] = Variable<int>(imgWidth);
    map['img_height'] = Variable<int>(imgHeight);
    map['history'] = Variable<String>(history);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  IllustrationsCompanion toCompanion(bool nullToAbsent) {
    return IllustrationsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      chapterId: Value(chapterId),
      afterParagraph: Value(afterParagraph),
      anchorOffset: Value(anchorOffset),
      anchorHash: Value(anchorHash),
      prompt: Value(prompt),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      status: Value(status),
      error: Value(error),
      imgWidth: Value(imgWidth),
      imgHeight: Value(imgHeight),
      history: Value(history),
      createdAt: Value(createdAt),
    );
  }

  factory Illustration.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Illustration(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      chapterId: serializer.fromJson<int>(json['chapterId']),
      afterParagraph: serializer.fromJson<int>(json['afterParagraph']),
      anchorOffset: serializer.fromJson<int>(json['anchorOffset']),
      anchorHash: serializer.fromJson<String>(json['anchorHash']),
      prompt: serializer.fromJson<String>(json['prompt']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String>(json['error']),
      imgWidth: serializer.fromJson<int>(json['imgWidth']),
      imgHeight: serializer.fromJson<int>(json['imgHeight']),
      history: serializer.fromJson<String>(json['history']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'chapterId': serializer.toJson<int>(chapterId),
      'afterParagraph': serializer.toJson<int>(afterParagraph),
      'anchorOffset': serializer.toJson<int>(anchorOffset),
      'anchorHash': serializer.toJson<String>(anchorHash),
      'prompt': serializer.toJson<String>(prompt),
      'imagePath': serializer.toJson<String?>(imagePath),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String>(error),
      'imgWidth': serializer.toJson<int>(imgWidth),
      'imgHeight': serializer.toJson<int>(imgHeight),
      'history': serializer.toJson<String>(history),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Illustration copyWith({
    int? id,
    int? bookId,
    int? chapterId,
    int? afterParagraph,
    int? anchorOffset,
    String? anchorHash,
    String? prompt,
    Value<String?> imagePath = const Value.absent(),
    String? status,
    String? error,
    int? imgWidth,
    int? imgHeight,
    String? history,
    DateTime? createdAt,
  }) => Illustration(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    chapterId: chapterId ?? this.chapterId,
    afterParagraph: afterParagraph ?? this.afterParagraph,
    anchorOffset: anchorOffset ?? this.anchorOffset,
    anchorHash: anchorHash ?? this.anchorHash,
    prompt: prompt ?? this.prompt,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    status: status ?? this.status,
    error: error ?? this.error,
    imgWidth: imgWidth ?? this.imgWidth,
    imgHeight: imgHeight ?? this.imgHeight,
    history: history ?? this.history,
    createdAt: createdAt ?? this.createdAt,
  );
  Illustration copyWithCompanion(IllustrationsCompanion data) {
    return Illustration(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      afterParagraph: data.afterParagraph.present
          ? data.afterParagraph.value
          : this.afterParagraph,
      anchorOffset: data.anchorOffset.present
          ? data.anchorOffset.value
          : this.anchorOffset,
      anchorHash: data.anchorHash.present
          ? data.anchorHash.value
          : this.anchorHash,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      imgWidth: data.imgWidth.present ? data.imgWidth.value : this.imgWidth,
      imgHeight: data.imgHeight.present ? data.imgHeight.value : this.imgHeight,
      history: data.history.present ? data.history.value : this.history,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Illustration(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterId: $chapterId, ')
          ..write('afterParagraph: $afterParagraph, ')
          ..write('anchorOffset: $anchorOffset, ')
          ..write('anchorHash: $anchorHash, ')
          ..write('prompt: $prompt, ')
          ..write('imagePath: $imagePath, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('imgWidth: $imgWidth, ')
          ..write('imgHeight: $imgHeight, ')
          ..write('history: $history, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    chapterId,
    afterParagraph,
    anchorOffset,
    anchorHash,
    prompt,
    imagePath,
    status,
    error,
    imgWidth,
    imgHeight,
    history,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Illustration &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.chapterId == this.chapterId &&
          other.afterParagraph == this.afterParagraph &&
          other.anchorOffset == this.anchorOffset &&
          other.anchorHash == this.anchorHash &&
          other.prompt == this.prompt &&
          other.imagePath == this.imagePath &&
          other.status == this.status &&
          other.error == this.error &&
          other.imgWidth == this.imgWidth &&
          other.imgHeight == this.imgHeight &&
          other.history == this.history &&
          other.createdAt == this.createdAt);
}

class IllustrationsCompanion extends UpdateCompanion<Illustration> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> chapterId;
  final Value<int> afterParagraph;
  final Value<int> anchorOffset;
  final Value<String> anchorHash;
  final Value<String> prompt;
  final Value<String?> imagePath;
  final Value<String> status;
  final Value<String> error;
  final Value<int> imgWidth;
  final Value<int> imgHeight;
  final Value<String> history;
  final Value<DateTime> createdAt;
  const IllustrationsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.afterParagraph = const Value.absent(),
    this.anchorOffset = const Value.absent(),
    this.anchorHash = const Value.absent(),
    this.prompt = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.imgWidth = const Value.absent(),
    this.imgHeight = const Value.absent(),
    this.history = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  IllustrationsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required int chapterId,
    required int afterParagraph,
    this.anchorOffset = const Value.absent(),
    required String anchorHash,
    required String prompt,
    this.imagePath = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.imgWidth = const Value.absent(),
    this.imgHeight = const Value.absent(),
    this.history = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : bookId = Value(bookId),
       chapterId = Value(chapterId),
       afterParagraph = Value(afterParagraph),
       anchorHash = Value(anchorHash),
       prompt = Value(prompt);
  static Insertable<Illustration> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? chapterId,
    Expression<int>? afterParagraph,
    Expression<int>? anchorOffset,
    Expression<String>? anchorHash,
    Expression<String>? prompt,
    Expression<String>? imagePath,
    Expression<String>? status,
    Expression<String>? error,
    Expression<int>? imgWidth,
    Expression<int>? imgHeight,
    Expression<String>? history,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (afterParagraph != null) 'after_paragraph': afterParagraph,
      if (anchorOffset != null) 'anchor_offset': anchorOffset,
      if (anchorHash != null) 'anchor_hash': anchorHash,
      if (prompt != null) 'prompt': prompt,
      if (imagePath != null) 'image_path': imagePath,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (imgWidth != null) 'img_width': imgWidth,
      if (imgHeight != null) 'img_height': imgHeight,
      if (history != null) 'history': history,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  IllustrationsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? chapterId,
    Value<int>? afterParagraph,
    Value<int>? anchorOffset,
    Value<String>? anchorHash,
    Value<String>? prompt,
    Value<String?>? imagePath,
    Value<String>? status,
    Value<String>? error,
    Value<int>? imgWidth,
    Value<int>? imgHeight,
    Value<String>? history,
    Value<DateTime>? createdAt,
  }) {
    return IllustrationsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      afterParagraph: afterParagraph ?? this.afterParagraph,
      anchorOffset: anchorOffset ?? this.anchorOffset,
      anchorHash: anchorHash ?? this.anchorHash,
      prompt: prompt ?? this.prompt,
      imagePath: imagePath ?? this.imagePath,
      status: status ?? this.status,
      error: error ?? this.error,
      imgWidth: imgWidth ?? this.imgWidth,
      imgHeight: imgHeight ?? this.imgHeight,
      history: history ?? this.history,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<int>(chapterId.value);
    }
    if (afterParagraph.present) {
      map['after_paragraph'] = Variable<int>(afterParagraph.value);
    }
    if (anchorOffset.present) {
      map['anchor_offset'] = Variable<int>(anchorOffset.value);
    }
    if (anchorHash.present) {
      map['anchor_hash'] = Variable<String>(anchorHash.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (imgWidth.present) {
      map['img_width'] = Variable<int>(imgWidth.value);
    }
    if (imgHeight.present) {
      map['img_height'] = Variable<int>(imgHeight.value);
    }
    if (history.present) {
      map['history'] = Variable<String>(history.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IllustrationsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterId: $chapterId, ')
          ..write('afterParagraph: $afterParagraph, ')
          ..write('anchorOffset: $anchorOffset, ')
          ..write('anchorHash: $anchorHash, ')
          ..write('prompt: $prompt, ')
          ..write('imagePath: $imagePath, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('imgWidth: $imgWidth, ')
          ..write('imgHeight: $imgHeight, ')
          ..write('history: $history, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $WorkflowsTable extends Workflows
    with TableInfo<$WorkflowsTable, Workflow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkflowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiJsonMeta = const VerificationMeta(
    'apiJson',
  );
  @override
  late final GeneratedColumn<String> apiJson = GeneratedColumn<String>(
    'api_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mappingMeta = const VerificationMeta(
    'mapping',
  );
  @override
  late final GeneratedColumn<String> mapping = GeneratedColumn<String>(
    'mapping',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isSecondMeta = const VerificationMeta(
    'isSecond',
  );
  @override
  late final GeneratedColumn<bool> isSecond = GeneratedColumn<bool>(
    'is_second',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_second" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    apiJson,
    mapping,
    isActive,
    isSecond,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workflows';
  @override
  VerificationContext validateIntegrity(
    Insertable<Workflow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('api_json')) {
      context.handle(
        _apiJsonMeta,
        apiJson.isAcceptableOrUnknown(data['api_json']!, _apiJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_apiJsonMeta);
    }
    if (data.containsKey('mapping')) {
      context.handle(
        _mappingMeta,
        mapping.isAcceptableOrUnknown(data['mapping']!, _mappingMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('is_second')) {
      context.handle(
        _isSecondMeta,
        isSecond.isAcceptableOrUnknown(data['is_second']!, _isSecondMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Workflow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Workflow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      apiJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_json'],
      )!,
      mapping: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      isSecond: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_second'],
      )!,
    );
  }

  @override
  $WorkflowsTable createAlias(String alias) {
    return $WorkflowsTable(attachedDatabase, alias);
  }
}

class Workflow extends DataClass implements Insertable<Workflow> {
  final int id;
  final String name;
  final String apiJson;
  final String mapping;
  final bool isActive;
  final bool isSecond;
  const Workflow({
    required this.id,
    required this.name,
    required this.apiJson,
    required this.mapping,
    required this.isActive,
    required this.isSecond,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['api_json'] = Variable<String>(apiJson);
    map['mapping'] = Variable<String>(mapping);
    map['is_active'] = Variable<bool>(isActive);
    map['is_second'] = Variable<bool>(isSecond);
    return map;
  }

  WorkflowsCompanion toCompanion(bool nullToAbsent) {
    return WorkflowsCompanion(
      id: Value(id),
      name: Value(name),
      apiJson: Value(apiJson),
      mapping: Value(mapping),
      isActive: Value(isActive),
      isSecond: Value(isSecond),
    );
  }

  factory Workflow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Workflow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      apiJson: serializer.fromJson<String>(json['apiJson']),
      mapping: serializer.fromJson<String>(json['mapping']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      isSecond: serializer.fromJson<bool>(json['isSecond']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'apiJson': serializer.toJson<String>(apiJson),
      'mapping': serializer.toJson<String>(mapping),
      'isActive': serializer.toJson<bool>(isActive),
      'isSecond': serializer.toJson<bool>(isSecond),
    };
  }

  Workflow copyWith({
    int? id,
    String? name,
    String? apiJson,
    String? mapping,
    bool? isActive,
    bool? isSecond,
  }) => Workflow(
    id: id ?? this.id,
    name: name ?? this.name,
    apiJson: apiJson ?? this.apiJson,
    mapping: mapping ?? this.mapping,
    isActive: isActive ?? this.isActive,
    isSecond: isSecond ?? this.isSecond,
  );
  Workflow copyWithCompanion(WorkflowsCompanion data) {
    return Workflow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      apiJson: data.apiJson.present ? data.apiJson.value : this.apiJson,
      mapping: data.mapping.present ? data.mapping.value : this.mapping,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      isSecond: data.isSecond.present ? data.isSecond.value : this.isSecond,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Workflow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('apiJson: $apiJson, ')
          ..write('mapping: $mapping, ')
          ..write('isActive: $isActive, ')
          ..write('isSecond: $isSecond')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, apiJson, mapping, isActive, isSecond);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Workflow &&
          other.id == this.id &&
          other.name == this.name &&
          other.apiJson == this.apiJson &&
          other.mapping == this.mapping &&
          other.isActive == this.isActive &&
          other.isSecond == this.isSecond);
}

class WorkflowsCompanion extends UpdateCompanion<Workflow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> apiJson;
  final Value<String> mapping;
  final Value<bool> isActive;
  final Value<bool> isSecond;
  const WorkflowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.apiJson = const Value.absent(),
    this.mapping = const Value.absent(),
    this.isActive = const Value.absent(),
    this.isSecond = const Value.absent(),
  });
  WorkflowsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String apiJson,
    this.mapping = const Value.absent(),
    this.isActive = const Value.absent(),
    this.isSecond = const Value.absent(),
  }) : name = Value(name),
       apiJson = Value(apiJson);
  static Insertable<Workflow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? apiJson,
    Expression<String>? mapping,
    Expression<bool>? isActive,
    Expression<bool>? isSecond,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (apiJson != null) 'api_json': apiJson,
      if (mapping != null) 'mapping': mapping,
      if (isActive != null) 'is_active': isActive,
      if (isSecond != null) 'is_second': isSecond,
    });
  }

  WorkflowsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? apiJson,
    Value<String>? mapping,
    Value<bool>? isActive,
    Value<bool>? isSecond,
  }) {
    return WorkflowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      apiJson: apiJson ?? this.apiJson,
      mapping: mapping ?? this.mapping,
      isActive: isActive ?? this.isActive,
      isSecond: isSecond ?? this.isSecond,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (apiJson.present) {
      map['api_json'] = Variable<String>(apiJson.value);
    }
    if (mapping.present) {
      map['mapping'] = Variable<String>(mapping.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (isSecond.present) {
      map['is_second'] = Variable<bool>(isSecond.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkflowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('apiJson: $apiJson, ')
          ..write('mapping: $mapping, ')
          ..write('isActive: $isActive, ')
          ..write('isSecond: $isSecond')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $IllustrationsTable illustrations = $IllustrationsTable(this);
  late final $WorkflowsTable workflows = $WorkflowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    chapters,
    illustrations,
    workflows,
  ];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      required String title,
      Value<String> author,
      required String format,
      Value<String> sourcePath,
      Value<DateTime> createdAt,
      Value<int> lastChapter,
      Value<int> lastParagraph,
      Value<String> lore,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> author,
      Value<String> format,
      Value<String> sourcePath,
      Value<DateTime> createdAt,
      Value<int> lastChapter,
      Value<int> lastParagraph,
      Value<String> lore,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ChaptersTable, List<Chapter>> _chaptersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: 'books__id__chapters__book_id',
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastChapter => $composableBuilder(
    column: $table.lastChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastParagraph => $composableBuilder(
    column: $table.lastParagraph,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lore => $composableBuilder(
    column: $table.lore,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastChapter => $composableBuilder(
    column: $table.lastChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastParagraph => $composableBuilder(
    column: $table.lastParagraph,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lore => $composableBuilder(
    column: $table.lore,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastChapter => $composableBuilder(
    column: $table.lastChapter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastParagraph => $composableBuilder(
    column: $table.lastParagraph,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lore =>
      $composableBuilder(column: $table.lore, builder: (column) => column);

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, $$BooksTableReferences),
          Book,
          PrefetchHooks Function({bool chaptersRefs})
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> lastChapter = const Value.absent(),
                Value<int> lastParagraph = const Value.absent(),
                Value<String> lore = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                format: format,
                sourcePath: sourcePath,
                createdAt: createdAt,
                lastChapter: lastChapter,
                lastParagraph: lastParagraph,
                lore: lore,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String> author = const Value.absent(),
                required String format,
                Value<String> sourcePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> lastChapter = const Value.absent(),
                Value<int> lastParagraph = const Value.absent(),
                Value<String> lore = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                format: format,
                sourcePath: sourcePath,
                createdAt: createdAt,
                lastChapter: lastChapter,
                lastParagraph: lastParagraph,
                lore: lore,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, Book>(table),
                  $$BooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chaptersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (chaptersRefs) db.chapters],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chaptersRefs)
                    await $_getPrefetchedData<Book, $BooksTable, Chapter>(
                      currentTable: table,
                      referencedTable: $$BooksTableReferences
                          ._chaptersRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BooksTableReferences(db, table, p0).chaptersRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.bookId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, $$BooksTableReferences),
      Book,
      PrefetchHooks Function({bool chaptersRefs})
    >;
typedef $$ChaptersTableCreateCompanionBuilder =
    ChaptersCompanion Function({
      Value<int> id,
      required int bookId,
      required int idx,
      required String title,
      required String content,
    });
typedef $$ChaptersTableUpdateCompanionBuilder =
    ChaptersCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<int> idx,
      Value<String> title,
      Value<String> content,
    });

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, Chapter> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('chapters__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get idx =>
      $composableBuilder(column: $table.idx, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          Chapter,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (Chapter, $$ChaptersTableReferences),
          Chapter,
          PrefetchHooks Function({bool bookId})
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> idx = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
              }) => ChaptersCompanion(
                id: id,
                bookId: bookId,
                idx: idx,
                title: title,
                content: content,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required int idx,
                required String title,
                required String content,
              }) => ChaptersCompanion.insert(
                id: id,
                bookId: bookId,
                idx: idx,
                title: title,
                content: content,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChaptersTable, Chapter>(table),
                  $$ChaptersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$ChaptersTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$ChaptersTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      Chapter,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (Chapter, $$ChaptersTableReferences),
      Chapter,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$IllustrationsTableCreateCompanionBuilder =
    IllustrationsCompanion Function({
      Value<int> id,
      required int bookId,
      required int chapterId,
      required int afterParagraph,
      Value<int> anchorOffset,
      required String anchorHash,
      required String prompt,
      Value<String?> imagePath,
      Value<String> status,
      Value<String> error,
      Value<int> imgWidth,
      Value<int> imgHeight,
      Value<String> history,
      Value<DateTime> createdAt,
    });
typedef $$IllustrationsTableUpdateCompanionBuilder =
    IllustrationsCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<int> chapterId,
      Value<int> afterParagraph,
      Value<int> anchorOffset,
      Value<String> anchorHash,
      Value<String> prompt,
      Value<String?> imagePath,
      Value<String> status,
      Value<String> error,
      Value<int> imgWidth,
      Value<int> imgHeight,
      Value<String> history,
      Value<DateTime> createdAt,
    });

class $$IllustrationsTableFilterComposer
    extends Composer<_$AppDatabase, $IllustrationsTable> {
  $$IllustrationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get afterParagraph => $composableBuilder(
    column: $table.afterParagraph,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchorHash => $composableBuilder(
    column: $table.anchorHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imgWidth => $composableBuilder(
    column: $table.imgWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imgHeight => $composableBuilder(
    column: $table.imgHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get history => $composableBuilder(
    column: $table.history,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IllustrationsTableOrderingComposer
    extends Composer<_$AppDatabase, $IllustrationsTable> {
  $$IllustrationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get afterParagraph => $composableBuilder(
    column: $table.afterParagraph,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchorHash => $composableBuilder(
    column: $table.anchorHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imgWidth => $composableBuilder(
    column: $table.imgWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imgHeight => $composableBuilder(
    column: $table.imgHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get history => $composableBuilder(
    column: $table.history,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IllustrationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IllustrationsTable> {
  $$IllustrationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<int> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<int> get afterParagraph => $composableBuilder(
    column: $table.afterParagraph,
    builder: (column) => column,
  );

  GeneratedColumn<int> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get anchorHash => $composableBuilder(
    column: $table.anchorHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get imgWidth =>
      $composableBuilder(column: $table.imgWidth, builder: (column) => column);

  GeneratedColumn<int> get imgHeight =>
      $composableBuilder(column: $table.imgHeight, builder: (column) => column);

  GeneratedColumn<String> get history =>
      $composableBuilder(column: $table.history, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$IllustrationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IllustrationsTable,
          Illustration,
          $$IllustrationsTableFilterComposer,
          $$IllustrationsTableOrderingComposer,
          $$IllustrationsTableAnnotationComposer,
          $$IllustrationsTableCreateCompanionBuilder,
          $$IllustrationsTableUpdateCompanionBuilder,
          (
            Illustration,
            BaseReferences<_$AppDatabase, $IllustrationsTable, Illustration>,
          ),
          Illustration,
          PrefetchHooks Function()
        > {
  $$IllustrationsTableTableManager(_$AppDatabase db, $IllustrationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IllustrationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IllustrationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IllustrationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> chapterId = const Value.absent(),
                Value<int> afterParagraph = const Value.absent(),
                Value<int> anchorOffset = const Value.absent(),
                Value<String> anchorHash = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> error = const Value.absent(),
                Value<int> imgWidth = const Value.absent(),
                Value<int> imgHeight = const Value.absent(),
                Value<String> history = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => IllustrationsCompanion(
                id: id,
                bookId: bookId,
                chapterId: chapterId,
                afterParagraph: afterParagraph,
                anchorOffset: anchorOffset,
                anchorHash: anchorHash,
                prompt: prompt,
                imagePath: imagePath,
                status: status,
                error: error,
                imgWidth: imgWidth,
                imgHeight: imgHeight,
                history: history,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required int chapterId,
                required int afterParagraph,
                Value<int> anchorOffset = const Value.absent(),
                required String anchorHash,
                required String prompt,
                Value<String?> imagePath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> error = const Value.absent(),
                Value<int> imgWidth = const Value.absent(),
                Value<int> imgHeight = const Value.absent(),
                Value<String> history = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => IllustrationsCompanion.insert(
                id: id,
                bookId: bookId,
                chapterId: chapterId,
                afterParagraph: afterParagraph,
                anchorOffset: anchorOffset,
                anchorHash: anchorHash,
                prompt: prompt,
                imagePath: imagePath,
                status: status,
                error: error,
                imgWidth: imgWidth,
                imgHeight: imgHeight,
                history: history,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IllustrationsTable, Illustration>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $IllustrationsTable,
                    Illustration
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IllustrationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IllustrationsTable,
      Illustration,
      $$IllustrationsTableFilterComposer,
      $$IllustrationsTableOrderingComposer,
      $$IllustrationsTableAnnotationComposer,
      $$IllustrationsTableCreateCompanionBuilder,
      $$IllustrationsTableUpdateCompanionBuilder,
      (
        Illustration,
        BaseReferences<_$AppDatabase, $IllustrationsTable, Illustration>,
      ),
      Illustration,
      PrefetchHooks Function()
    >;
typedef $$WorkflowsTableCreateCompanionBuilder =
    WorkflowsCompanion Function({
      Value<int> id,
      required String name,
      required String apiJson,
      Value<String> mapping,
      Value<bool> isActive,
      Value<bool> isSecond,
    });
typedef $$WorkflowsTableUpdateCompanionBuilder =
    WorkflowsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> apiJson,
      Value<String> mapping,
      Value<bool> isActive,
      Value<bool> isSecond,
    });

class $$WorkflowsTableFilterComposer
    extends Composer<_$AppDatabase, $WorkflowsTable> {
  $$WorkflowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiJson => $composableBuilder(
    column: $table.apiJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mapping => $composableBuilder(
    column: $table.mapping,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSecond => $composableBuilder(
    column: $table.isSecond,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkflowsTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkflowsTable> {
  $$WorkflowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiJson => $composableBuilder(
    column: $table.apiJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mapping => $composableBuilder(
    column: $table.mapping,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSecond => $composableBuilder(
    column: $table.isSecond,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkflowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkflowsTable> {
  $$WorkflowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get apiJson =>
      $composableBuilder(column: $table.apiJson, builder: (column) => column);

  GeneratedColumn<String> get mapping =>
      $composableBuilder(column: $table.mapping, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get isSecond =>
      $composableBuilder(column: $table.isSecond, builder: (column) => column);
}

class $$WorkflowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkflowsTable,
          Workflow,
          $$WorkflowsTableFilterComposer,
          $$WorkflowsTableOrderingComposer,
          $$WorkflowsTableAnnotationComposer,
          $$WorkflowsTableCreateCompanionBuilder,
          $$WorkflowsTableUpdateCompanionBuilder,
          (Workflow, BaseReferences<_$AppDatabase, $WorkflowsTable, Workflow>),
          Workflow,
          PrefetchHooks Function()
        > {
  $$WorkflowsTableTableManager(_$AppDatabase db, $WorkflowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkflowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkflowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkflowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> apiJson = const Value.absent(),
                Value<String> mapping = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> isSecond = const Value.absent(),
              }) => WorkflowsCompanion(
                id: id,
                name: name,
                apiJson: apiJson,
                mapping: mapping,
                isActive: isActive,
                isSecond: isSecond,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String apiJson,
                Value<String> mapping = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> isSecond = const Value.absent(),
              }) => WorkflowsCompanion.insert(
                id: id,
                name: name,
                apiJson: apiJson,
                mapping: mapping,
                isActive: isActive,
                isSecond: isSecond,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkflowsTable, Workflow>(table),
                  BaseReferences<_$AppDatabase, $WorkflowsTable, Workflow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkflowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkflowsTable,
      Workflow,
      $$WorkflowsTableFilterComposer,
      $$WorkflowsTableOrderingComposer,
      $$WorkflowsTableAnnotationComposer,
      $$WorkflowsTableCreateCompanionBuilder,
      $$WorkflowsTableUpdateCompanionBuilder,
      (Workflow, BaseReferences<_$AppDatabase, $WorkflowsTable, Workflow>),
      Workflow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$IllustrationsTableTableManager get illustrations =>
      $$IllustrationsTableTableManager(_db, _db.illustrations);
  $$WorkflowsTableTableManager get workflows =>
      $$WorkflowsTableTableManager(_db, _db.workflows);
}
