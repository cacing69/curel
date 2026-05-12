// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crash_log_model.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCrashLogCollection on Isar {
  IsarCollection<CrashLog> get crashLogs => this.collection();
}

const CrashLogSchema = CollectionSchema(
  name: r'CrashLog',
  id: -3005803319669503613,
  properties: {
    r'context': PropertySchema(id: 0, name: r'context', type: IsarType.string),
    r'message': PropertySchema(id: 1, name: r'message', type: IsarType.string),
    r'severity': PropertySchema(id: 2, name: r'severity', type: IsarType.long),
    r'stackTrace': PropertySchema(
      id: 3,
      name: r'stackTrace',
      type: IsarType.string,
    ),
    r'timestamp': PropertySchema(
      id: 4,
      name: r'timestamp',
      type: IsarType.dateTime,
    ),
  },

  estimateSize: _crashLogEstimateSize,
  serialize: _crashLogSerialize,
  deserialize: _crashLogDeserialize,
  deserializeProp: _crashLogDeserializeProp,
  idName: r'id',
  indexes: {
    r'timestamp': IndexSchema(
      id: 1852253767416892198,
      name: r'timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'severity': IndexSchema(
      id: -5078743595604092464,
      name: r'severity',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'severity',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'context_timestamp': IndexSchema(
      id: 439819973002603218,
      name: r'context_timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'context',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _crashLogGetId,
  getLinks: _crashLogGetLinks,
  attach: _crashLogAttach,
  version: '3.3.2',
);

int _crashLogEstimateSize(
  CrashLog object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.context.length * 3;
  bytesCount += 3 + object.message.length * 3;
  {
    final value = object.stackTrace;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _crashLogSerialize(
  CrashLog object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.context);
  writer.writeString(offsets[1], object.message);
  writer.writeLong(offsets[2], object.severity);
  writer.writeString(offsets[3], object.stackTrace);
  writer.writeDateTime(offsets[4], object.timestamp);
}

CrashLog _crashLogDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CrashLog(
    context: reader.readString(offsets[0]),
    message: reader.readString(offsets[1]),
    severity: reader.readLong(offsets[2]),
    stackTrace: reader.readStringOrNull(offsets[3]),
    timestamp: reader.readDateTime(offsets[4]),
  );
  object.id = id;
  return object;
}

P _crashLogDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _crashLogGetId(CrashLog object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _crashLogGetLinks(CrashLog object) {
  return [];
}

void _crashLogAttach(IsarCollection<dynamic> col, Id id, CrashLog object) {
  object.id = id;
}

extension CrashLogQueryWhereSort on QueryBuilder<CrashLog, CrashLog, QWhere> {
  QueryBuilder<CrashLog, CrashLog, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhere> anyTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'timestamp'),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhere> anySeverity() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'severity'),
      );
    });
  }
}

extension CrashLogQueryWhere on QueryBuilder<CrashLog, CrashLog, QWhereClause> {
  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> timestampEqualTo(
    DateTime timestamp,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'timestamp', value: [timestamp]),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> timestampNotEqualTo(
    DateTime timestamp,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'timestamp',
                lower: [],
                upper: [timestamp],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'timestamp',
                lower: [timestamp],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'timestamp',
                lower: [timestamp],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'timestamp',
                lower: [],
                upper: [timestamp],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> timestampGreaterThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'timestamp',
          lower: [timestamp],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> timestampLessThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'timestamp',
          lower: [],
          upper: [timestamp],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> timestampBetween(
    DateTime lowerTimestamp,
    DateTime upperTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'timestamp',
          lower: [lowerTimestamp],
          includeLower: includeLower,
          upper: [upperTimestamp],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> severityEqualTo(
    int severity,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'severity', value: [severity]),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> severityNotEqualTo(
    int severity,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'severity',
                lower: [],
                upper: [severity],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'severity',
                lower: [severity],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'severity',
                lower: [severity],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'severity',
                lower: [],
                upper: [severity],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> severityGreaterThan(
    int severity, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'severity',
          lower: [severity],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> severityLessThan(
    int severity, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'severity',
          lower: [],
          upper: [severity],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> severityBetween(
    int lowerSeverity,
    int upperSeverity, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'severity',
          lower: [lowerSeverity],
          includeLower: includeLower,
          upper: [upperSeverity],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextEqualToAnyTimestamp(String context) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'context_timestamp',
          value: [context],
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextNotEqualToAnyTimestamp(String context) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [],
                upper: [context],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [],
                upper: [context],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause> contextTimestampEqualTo(
    String context,
    DateTime timestamp,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'context_timestamp',
          value: [context, timestamp],
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextEqualToTimestampNotEqualTo(String context, DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context],
                upper: [context, timestamp],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context, timestamp],
                includeLower: false,
                upper: [context],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context, timestamp],
                includeLower: false,
                upper: [context],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'context_timestamp',
                lower: [context],
                upper: [context, timestamp],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextEqualToTimestampGreaterThan(
    String context,
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'context_timestamp',
          lower: [context, timestamp],
          includeLower: include,
          upper: [context],
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextEqualToTimestampLessThan(
    String context,
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'context_timestamp',
          lower: [context],
          upper: [context, timestamp],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterWhereClause>
  contextEqualToTimestampBetween(
    String context,
    DateTime lowerTimestamp,
    DateTime upperTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'context_timestamp',
          lower: [context, lowerTimestamp],
          includeLower: includeLower,
          upper: [context, upperTimestamp],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CrashLogQueryFilter
    on QueryBuilder<CrashLog, CrashLog, QFilterCondition> {
  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'context',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'context',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'context',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'context', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> contextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'context', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'message',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'message',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'message',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'message', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> messageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'message', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> severityEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'severity', value: value),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> severityGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'severity',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> severityLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'severity',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> severityBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'severity',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'stackTrace'),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition>
  stackTraceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'stackTrace'),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'stackTrace',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'stackTrace',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'stackTrace',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> stackTraceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'stackTrace', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition>
  stackTraceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'stackTrace', value: ''),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> timestampEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'timestamp', value: value),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'timestamp',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'timestamp',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterFilterCondition> timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'timestamp',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CrashLogQueryObject
    on QueryBuilder<CrashLog, CrashLog, QFilterCondition> {}

extension CrashLogQueryLinks
    on QueryBuilder<CrashLog, CrashLog, QFilterCondition> {}

extension CrashLogQuerySortBy on QueryBuilder<CrashLog, CrashLog, QSortBy> {
  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByContext() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'context', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByContextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'context', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortBySeverity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'severity', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortBySeverityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'severity', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByStackTrace() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stackTrace', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByStackTraceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stackTrace', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension CrashLogQuerySortThenBy
    on QueryBuilder<CrashLog, CrashLog, QSortThenBy> {
  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByContext() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'context', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByContextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'context', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenBySeverity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'severity', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenBySeverityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'severity', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByStackTrace() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stackTrace', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByStackTraceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stackTrace', Sort.desc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QAfterSortBy> thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension CrashLogQueryWhereDistinct
    on QueryBuilder<CrashLog, CrashLog, QDistinct> {
  QueryBuilder<CrashLog, CrashLog, QDistinct> distinctByContext({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'context', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QDistinct> distinctByMessage({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'message', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QDistinct> distinctBySeverity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'severity');
    });
  }

  QueryBuilder<CrashLog, CrashLog, QDistinct> distinctByStackTrace({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stackTrace', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CrashLog, CrashLog, QDistinct> distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }
}

extension CrashLogQueryProperty
    on QueryBuilder<CrashLog, CrashLog, QQueryProperty> {
  QueryBuilder<CrashLog, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CrashLog, String, QQueryOperations> contextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'context');
    });
  }

  QueryBuilder<CrashLog, String, QQueryOperations> messageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'message');
    });
  }

  QueryBuilder<CrashLog, int, QQueryOperations> severityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'severity');
    });
  }

  QueryBuilder<CrashLog, String?, QQueryOperations> stackTraceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stackTrace');
    });
  }

  QueryBuilder<CrashLog, DateTime, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }
}
