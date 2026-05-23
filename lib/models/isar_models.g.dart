// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isar_models.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalProfileCollection on Isar {
  IsarCollection<LocalProfile> get localProfiles => this.collection();
}

const LocalProfileSchema = CollectionSchema(
  name: r'LocalProfile',
  id: -3481655517967548928,
  properties: {
    r'avatarUrl': PropertySchema(
      id: 0,
      name: r'avatarUrl',
      type: IsarType.string,
    ),
    r'bio': PropertySchema(
      id: 1,
      name: r'bio',
      type: IsarType.string,
    ),
    r'displayName': PropertySchema(
      id: 2,
      name: r'displayName',
      type: IsarType.string,
    ),
    r'facebookHandle': PropertySchema(
      id: 3,
      name: r'facebookHandle',
      type: IsarType.string,
    ),
    r'instagramHandle': PropertySchema(
      id: 4,
      name: r'instagramHandle',
      type: IsarType.string,
    ),
    r'isSynced': PropertySchema(
      id: 5,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'lastSeen': PropertySchema(
      id: 6,
      name: r'lastSeen',
      type: IsarType.dateTime,
    ),
    r'publicKey': PropertySchema(
      id: 7,
      name: r'publicKey',
      type: IsarType.string,
    ),
    r'sessionKey': PropertySchema(
      id: 8,
      name: r'sessionKey',
      type: IsarType.string,
    ),
    r'tiktokHandle': PropertySchema(
      id: 9,
      name: r'tiktokHandle',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 10,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'userId': PropertySchema(
      id: 11,
      name: r'userId',
      type: IsarType.string,
    ),
    r'version': PropertySchema(
      id: 12,
      name: r'version',
      type: IsarType.long,
    ),
    r'zoneId': PropertySchema(
      id: 13,
      name: r'zoneId',
      type: IsarType.string,
    )
  },
  estimateSize: _localProfileEstimateSize,
  serialize: _localProfileSerialize,
  deserialize: _localProfileDeserialize,
  deserializeProp: _localProfileDeserializeProp,
  idName: r'id',
  indexes: {
    r'userId': IndexSchema(
      id: -2005826577402374815,
      name: r'userId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'userId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'zoneId': IndexSchema(
      id: 6983029780105030646,
      name: r'zoneId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'zoneId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _localProfileGetId,
  getLinks: _localProfileGetLinks,
  attach: _localProfileAttach,
  version: '3.1.0+1',
);

int _localProfileEstimateSize(
  LocalProfile object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.avatarUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.bio;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.displayName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.facebookHandle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.instagramHandle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.publicKey;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sessionKey;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.tiktokHandle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.userId.length * 3;
  bytesCount += 3 + object.zoneId.length * 3;
  return bytesCount;
}

void _localProfileSerialize(
  LocalProfile object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.avatarUrl);
  writer.writeString(offsets[1], object.bio);
  writer.writeString(offsets[2], object.displayName);
  writer.writeString(offsets[3], object.facebookHandle);
  writer.writeString(offsets[4], object.instagramHandle);
  writer.writeBool(offsets[5], object.isSynced);
  writer.writeDateTime(offsets[6], object.lastSeen);
  writer.writeString(offsets[7], object.publicKey);
  writer.writeString(offsets[8], object.sessionKey);
  writer.writeString(offsets[9], object.tiktokHandle);
  writer.writeDateTime(offsets[10], object.updatedAt);
  writer.writeString(offsets[11], object.userId);
  writer.writeLong(offsets[12], object.version);
  writer.writeString(offsets[13], object.zoneId);
}

LocalProfile _localProfileDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalProfile();
  object.avatarUrl = reader.readStringOrNull(offsets[0]);
  object.bio = reader.readStringOrNull(offsets[1]);
  object.displayName = reader.readStringOrNull(offsets[2]);
  object.facebookHandle = reader.readStringOrNull(offsets[3]);
  object.id = id;
  object.instagramHandle = reader.readStringOrNull(offsets[4]);
  object.isSynced = reader.readBool(offsets[5]);
  object.lastSeen = reader.readDateTimeOrNull(offsets[6]);
  object.publicKey = reader.readStringOrNull(offsets[7]);
  object.sessionKey = reader.readStringOrNull(offsets[8]);
  object.tiktokHandle = reader.readStringOrNull(offsets[9]);
  object.updatedAt = reader.readDateTime(offsets[10]);
  object.userId = reader.readString(offsets[11]);
  object.version = reader.readLong(offsets[12]);
  object.zoneId = reader.readString(offsets[13]);
  return object;
}

P _localProfileDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readDateTime(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    case 12:
      return (reader.readLong(offset)) as P;
    case 13:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localProfileGetId(LocalProfile object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localProfileGetLinks(LocalProfile object) {
  return [];
}

void _localProfileAttach(
    IsarCollection<dynamic> col, Id id, LocalProfile object) {
  object.id = id;
}

extension LocalProfileByIndex on IsarCollection<LocalProfile> {
  Future<LocalProfile?> getByUserId(String userId) {
    return getByIndex(r'userId', [userId]);
  }

  LocalProfile? getByUserIdSync(String userId) {
    return getByIndexSync(r'userId', [userId]);
  }

  Future<bool> deleteByUserId(String userId) {
    return deleteByIndex(r'userId', [userId]);
  }

  bool deleteByUserIdSync(String userId) {
    return deleteByIndexSync(r'userId', [userId]);
  }

  Future<List<LocalProfile?>> getAllByUserId(List<String> userIdValues) {
    final values = userIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'userId', values);
  }

  List<LocalProfile?> getAllByUserIdSync(List<String> userIdValues) {
    final values = userIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'userId', values);
  }

  Future<int> deleteAllByUserId(List<String> userIdValues) {
    final values = userIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'userId', values);
  }

  int deleteAllByUserIdSync(List<String> userIdValues) {
    final values = userIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'userId', values);
  }

  Future<Id> putByUserId(LocalProfile object) {
    return putByIndex(r'userId', object);
  }

  Id putByUserIdSync(LocalProfile object, {bool saveLinks = true}) {
    return putByIndexSync(r'userId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByUserId(List<LocalProfile> objects) {
    return putAllByIndex(r'userId', objects);
  }

  List<Id> putAllByUserIdSync(List<LocalProfile> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'userId', objects, saveLinks: saveLinks);
  }

  Future<LocalProfile?> getByZoneId(String zoneId) {
    return getByIndex(r'zoneId', [zoneId]);
  }

  LocalProfile? getByZoneIdSync(String zoneId) {
    return getByIndexSync(r'zoneId', [zoneId]);
  }

  Future<bool> deleteByZoneId(String zoneId) {
    return deleteByIndex(r'zoneId', [zoneId]);
  }

  bool deleteByZoneIdSync(String zoneId) {
    return deleteByIndexSync(r'zoneId', [zoneId]);
  }

  Future<List<LocalProfile?>> getAllByZoneId(List<String> zoneIdValues) {
    final values = zoneIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'zoneId', values);
  }

  List<LocalProfile?> getAllByZoneIdSync(List<String> zoneIdValues) {
    final values = zoneIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'zoneId', values);
  }

  Future<int> deleteAllByZoneId(List<String> zoneIdValues) {
    final values = zoneIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'zoneId', values);
  }

  int deleteAllByZoneIdSync(List<String> zoneIdValues) {
    final values = zoneIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'zoneId', values);
  }

  Future<Id> putByZoneId(LocalProfile object) {
    return putByIndex(r'zoneId', object);
  }

  Id putByZoneIdSync(LocalProfile object, {bool saveLinks = true}) {
    return putByIndexSync(r'zoneId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByZoneId(List<LocalProfile> objects) {
    return putAllByIndex(r'zoneId', objects);
  }

  List<Id> putAllByZoneIdSync(List<LocalProfile> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'zoneId', objects, saveLinks: saveLinks);
  }
}

extension LocalProfileQueryWhereSort
    on QueryBuilder<LocalProfile, LocalProfile, QWhere> {
  QueryBuilder<LocalProfile, LocalProfile, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension LocalProfileQueryWhere
    on QueryBuilder<LocalProfile, LocalProfile, QWhereClause> {
  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> userIdEqualTo(
      String userId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'userId',
        value: [userId],
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> userIdNotEqualTo(
      String userId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [],
              upper: [userId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [userId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [userId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [],
              upper: [userId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> zoneIdEqualTo(
      String zoneId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'zoneId',
        value: [zoneId],
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterWhereClause> zoneIdNotEqualTo(
      String zoneId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'zoneId',
              lower: [],
              upper: [zoneId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'zoneId',
              lower: [zoneId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'zoneId',
              lower: [zoneId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'zoneId',
              lower: [],
              upper: [zoneId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension LocalProfileQueryFilter
    on QueryBuilder<LocalProfile, LocalProfile, QFilterCondition> {
  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avatarUrl',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avatarUrl',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avatarUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'avatarUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'avatarUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      avatarUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'avatarUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'bio',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      bioIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'bio',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      bioGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bio',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'bio',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'bio',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> bioIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bio',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      bioIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'bio',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'displayName',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'displayName',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'displayName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'displayName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'displayName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayName',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      displayNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'displayName',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'facebookHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'facebookHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'facebookHandle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facebookHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facebookHandle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facebookHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      facebookHandleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facebookHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'instagramHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'instagramHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'instagramHandle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'instagramHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'instagramHandle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'instagramHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      instagramHandleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'instagramHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSeen',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSeen',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSeen',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSeen',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSeen',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      lastSeenBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSeen',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'publicKey',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'publicKey',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'publicKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'publicKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'publicKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'publicKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      publicKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'publicKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sessionKey',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sessionKey',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sessionKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sessionKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      sessionKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sessionKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'tiktokHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'tiktokHandle',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tiktokHandle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'tiktokHandle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'tiktokHandle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tiktokHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      tiktokHandleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'tiktokHandle',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> userIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> userIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> userIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      userIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      versionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      versionGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      versionLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'version',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      versionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'version',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> zoneIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> zoneIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'zoneId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'zoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition> zoneIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'zoneId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'zoneId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterFilterCondition>
      zoneIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'zoneId',
        value: '',
      ));
    });
  }
}

extension LocalProfileQueryObject
    on QueryBuilder<LocalProfile, LocalProfile, QFilterCondition> {}

extension LocalProfileQueryLinks
    on QueryBuilder<LocalProfile, LocalProfile, QFilterCondition> {}

extension LocalProfileQuerySortBy
    on QueryBuilder<LocalProfile, LocalProfile, QSortBy> {
  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByAvatarUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByAvatarUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByBio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bio', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByBioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bio', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByFacebookHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facebookHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByFacebookHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facebookHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByInstagramHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'instagramHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByInstagramHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'instagramHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByLastSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByPublicKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKey', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByPublicKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKey', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortBySessionKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionKey', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortBySessionKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionKey', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByTiktokHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tiktokHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      sortByTiktokHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tiktokHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zoneId', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> sortByZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zoneId', Sort.desc);
    });
  }
}

extension LocalProfileQuerySortThenBy
    on QueryBuilder<LocalProfile, LocalProfile, QSortThenBy> {
  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByAvatarUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByAvatarUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByBio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bio', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByBioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bio', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByFacebookHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facebookHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByFacebookHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facebookHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByInstagramHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'instagramHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByInstagramHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'instagramHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByLastSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByPublicKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKey', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByPublicKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKey', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenBySessionKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionKey', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenBySessionKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionKey', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByTiktokHandle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tiktokHandle', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy>
      thenByTiktokHandleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tiktokHandle', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'version', Sort.desc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zoneId', Sort.asc);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QAfterSortBy> thenByZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zoneId', Sort.desc);
    });
  }
}

extension LocalProfileQueryWhereDistinct
    on QueryBuilder<LocalProfile, LocalProfile, QDistinct> {
  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByAvatarUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avatarUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByBio(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bio', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByDisplayName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByFacebookHandle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facebookHandle',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByInstagramHandle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'instagramHandle',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSeen');
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByPublicKey(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'publicKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctBySessionKey(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByTiktokHandle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tiktokHandle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByUserId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'version');
    });
  }

  QueryBuilder<LocalProfile, LocalProfile, QDistinct> distinctByZoneId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'zoneId', caseSensitive: caseSensitive);
    });
  }
}

extension LocalProfileQueryProperty
    on QueryBuilder<LocalProfile, LocalProfile, QQueryProperty> {
  QueryBuilder<LocalProfile, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> avatarUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avatarUrl');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> bioProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bio');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> displayNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayName');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations>
      facebookHandleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facebookHandle');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations>
      instagramHandleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'instagramHandle');
    });
  }

  QueryBuilder<LocalProfile, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalProfile, DateTime?, QQueryOperations> lastSeenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSeen');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> publicKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'publicKey');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> sessionKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionKey');
    });
  }

  QueryBuilder<LocalProfile, String?, QQueryOperations> tiktokHandleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tiktokHandle');
    });
  }

  QueryBuilder<LocalProfile, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<LocalProfile, String, QQueryOperations> userIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userId');
    });
  }

  QueryBuilder<LocalProfile, int, QQueryOperations> versionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'version');
    });
  }

  QueryBuilder<LocalProfile, String, QQueryOperations> zoneIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'zoneId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalEncounterCollection on Isar {
  IsarCollection<LocalEncounter> get localEncounters => this.collection();
}

const LocalEncounterSchema = CollectionSchema(
  name: r'LocalEncounter',
  id: 5650067863949151269,
  properties: {
    r'isSynced': PropertySchema(
      id: 0,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'latitude': PropertySchema(
      id: 1,
      name: r'latitude',
      type: IsarType.double,
    ),
    r'longitude': PropertySchema(
      id: 2,
      name: r'longitude',
      type: IsarType.double,
    ),
    r'otherZoneId': PropertySchema(
      id: 3,
      name: r'otherZoneId',
      type: IsarType.string,
    ),
    r'seenAt': PropertySchema(
      id: 4,
      name: r'seenAt',
      type: IsarType.dateTime,
    ),
    r'userId': PropertySchema(
      id: 5,
      name: r'userId',
      type: IsarType.string,
    )
  },
  estimateSize: _localEncounterEstimateSize,
  serialize: _localEncounterSerialize,
  deserialize: _localEncounterDeserialize,
  deserializeProp: _localEncounterDeserializeProp,
  idName: r'id',
  indexes: {
    r'seenAt': IndexSchema(
      id: 6626738466613815315,
      name: r'seenAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'seenAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _localEncounterGetId,
  getLinks: _localEncounterGetLinks,
  attach: _localEncounterAttach,
  version: '3.1.0+1',
);

int _localEncounterEstimateSize(
  LocalEncounter object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.otherZoneId.length * 3;
  bytesCount += 3 + object.userId.length * 3;
  return bytesCount;
}

void _localEncounterSerialize(
  LocalEncounter object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.isSynced);
  writer.writeDouble(offsets[1], object.latitude);
  writer.writeDouble(offsets[2], object.longitude);
  writer.writeString(offsets[3], object.otherZoneId);
  writer.writeDateTime(offsets[4], object.seenAt);
  writer.writeString(offsets[5], object.userId);
}

LocalEncounter _localEncounterDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalEncounter();
  object.id = id;
  object.isSynced = reader.readBool(offsets[0]);
  object.latitude = reader.readDoubleOrNull(offsets[1]);
  object.longitude = reader.readDoubleOrNull(offsets[2]);
  object.otherZoneId = reader.readString(offsets[3]);
  object.seenAt = reader.readDateTime(offsets[4]);
  object.userId = reader.readString(offsets[5]);
  return object;
}

P _localEncounterDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readDoubleOrNull(offset)) as P;
    case 2:
      return (reader.readDoubleOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localEncounterGetId(LocalEncounter object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localEncounterGetLinks(LocalEncounter object) {
  return [];
}

void _localEncounterAttach(
    IsarCollection<dynamic> col, Id id, LocalEncounter object) {
  object.id = id;
}

extension LocalEncounterQueryWhereSort
    on QueryBuilder<LocalEncounter, LocalEncounter, QWhere> {
  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhere> anySeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'seenAt'),
      );
    });
  }
}

extension LocalEncounterQueryWhere
    on QueryBuilder<LocalEncounter, LocalEncounter, QWhereClause> {
  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> seenAtEqualTo(
      DateTime seenAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'seenAt',
        value: [seenAt],
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause>
      seenAtNotEqualTo(DateTime seenAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'seenAt',
              lower: [],
              upper: [seenAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'seenAt',
              lower: [seenAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'seenAt',
              lower: [seenAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'seenAt',
              lower: [],
              upper: [seenAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause>
      seenAtGreaterThan(
    DateTime seenAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'seenAt',
        lower: [seenAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause>
      seenAtLessThan(
    DateTime seenAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'seenAt',
        lower: [],
        upper: [seenAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterWhereClause> seenAtBetween(
    DateTime lowerSeenAt,
    DateTime upperSeenAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'seenAt',
        lower: [lowerSeenAt],
        includeLower: includeLower,
        upper: [upperSeenAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension LocalEncounterQueryFilter
    on QueryBuilder<LocalEncounter, LocalEncounter, QFilterCondition> {
  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      latitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'latitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      longitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'longitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'otherZoneId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'otherZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'otherZoneId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'otherZoneId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      otherZoneIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'otherZoneId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      seenAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'seenAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      seenAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'seenAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      seenAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'seenAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      seenAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'seenAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterFilterCondition>
      userIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userId',
        value: '',
      ));
    });
  }
}

extension LocalEncounterQueryObject
    on QueryBuilder<LocalEncounter, LocalEncounter, QFilterCondition> {}

extension LocalEncounterQueryLinks
    on QueryBuilder<LocalEncounter, LocalEncounter, QFilterCondition> {}

extension LocalEncounterQuerySortBy
    on QueryBuilder<LocalEncounter, LocalEncounter, QSortBy> {
  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> sortByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> sortByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByOtherZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'otherZoneId', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByOtherZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'otherZoneId', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> sortBySeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seenAt', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortBySeenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seenAt', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> sortByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      sortByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension LocalEncounterQuerySortThenBy
    on QueryBuilder<LocalEncounter, LocalEncounter, QSortThenBy> {
  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByOtherZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'otherZoneId', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByOtherZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'otherZoneId', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenBySeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seenAt', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenBySeenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seenAt', Sort.desc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy> thenByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QAfterSortBy>
      thenByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension LocalEncounterQueryWhereDistinct
    on QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> {
  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> distinctByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'latitude');
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct>
      distinctByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'longitude');
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> distinctByOtherZoneId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'otherZoneId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> distinctBySeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'seenAt');
    });
  }

  QueryBuilder<LocalEncounter, LocalEncounter, QDistinct> distinctByUserId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userId', caseSensitive: caseSensitive);
    });
  }
}

extension LocalEncounterQueryProperty
    on QueryBuilder<LocalEncounter, LocalEncounter, QQueryProperty> {
  QueryBuilder<LocalEncounter, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalEncounter, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalEncounter, double?, QQueryOperations> latitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'latitude');
    });
  }

  QueryBuilder<LocalEncounter, double?, QQueryOperations> longitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'longitude');
    });
  }

  QueryBuilder<LocalEncounter, String, QQueryOperations> otherZoneIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'otherZoneId');
    });
  }

  QueryBuilder<LocalEncounter, DateTime, QQueryOperations> seenAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'seenAt');
    });
  }

  QueryBuilder<LocalEncounter, String, QQueryOperations> userIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalMessageCollection on Isar {
  IsarCollection<LocalMessage> get localMessages => this.collection();
}

const LocalMessageSchema = CollectionSchema(
  name: r'LocalMessage',
  id: 1045835317208282169,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'encryptedContent': PropertySchema(
      id: 1,
      name: r'encryptedContent',
      type: IsarType.string,
    ),
    r'hopCount': PropertySchema(
      id: 2,
      name: r'hopCount',
      type: IsarType.long,
    ),
    r'isP2p': PropertySchema(
      id: 3,
      name: r'isP2p',
      type: IsarType.bool,
    ),
    r'isSynced': PropertySchema(
      id: 4,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'mac': PropertySchema(
      id: 5,
      name: r'mac',
      type: IsarType.string,
    ),
    r'matchId': PropertySchema(
      id: 6,
      name: r'matchId',
      type: IsarType.string,
    ),
    r'messageId': PropertySchema(
      id: 7,
      name: r'messageId',
      type: IsarType.string,
    ),
    r'nonce': PropertySchema(
      id: 8,
      name: r'nonce',
      type: IsarType.string,
    ),
    r'receiverId': PropertySchema(
      id: 9,
      name: r'receiverId',
      type: IsarType.string,
    ),
    r'senderId': PropertySchema(
      id: 10,
      name: r'senderId',
      type: IsarType.string,
    )
  },
  estimateSize: _localMessageEstimateSize,
  serialize: _localMessageSerialize,
  deserialize: _localMessageDeserialize,
  deserializeProp: _localMessageDeserializeProp,
  idName: r'id',
  indexes: {
    r'messageId': IndexSchema(
      id: -635287409172016016,
      name: r'messageId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'messageId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'matchId': IndexSchema(
      id: -6517933327003962923,
      name: r'matchId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'matchId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: -3433535483987302584,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _localMessageGetId,
  getLinks: _localMessageGetLinks,
  attach: _localMessageAttach,
  version: '3.1.0+1',
);

int _localMessageEstimateSize(
  LocalMessage object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.encryptedContent.length * 3;
  bytesCount += 3 + object.mac.length * 3;
  bytesCount += 3 + object.matchId.length * 3;
  bytesCount += 3 + object.messageId.length * 3;
  bytesCount += 3 + object.nonce.length * 3;
  bytesCount += 3 + object.receiverId.length * 3;
  bytesCount += 3 + object.senderId.length * 3;
  return bytesCount;
}

void _localMessageSerialize(
  LocalMessage object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeString(offsets[1], object.encryptedContent);
  writer.writeLong(offsets[2], object.hopCount);
  writer.writeBool(offsets[3], object.isP2p);
  writer.writeBool(offsets[4], object.isSynced);
  writer.writeString(offsets[5], object.mac);
  writer.writeString(offsets[6], object.matchId);
  writer.writeString(offsets[7], object.messageId);
  writer.writeString(offsets[8], object.nonce);
  writer.writeString(offsets[9], object.receiverId);
  writer.writeString(offsets[10], object.senderId);
}

LocalMessage _localMessageDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalMessage();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.encryptedContent = reader.readString(offsets[1]);
  object.hopCount = reader.readLong(offsets[2]);
  object.id = id;
  object.isP2p = reader.readBool(offsets[3]);
  object.isSynced = reader.readBool(offsets[4]);
  object.mac = reader.readString(offsets[5]);
  object.matchId = reader.readString(offsets[6]);
  object.messageId = reader.readString(offsets[7]);
  object.nonce = reader.readString(offsets[8]);
  object.receiverId = reader.readString(offsets[9]);
  object.senderId = reader.readString(offsets[10]);
  return object;
}

P _localMessageDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localMessageGetId(LocalMessage object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localMessageGetLinks(LocalMessage object) {
  return [];
}

void _localMessageAttach(
    IsarCollection<dynamic> col, Id id, LocalMessage object) {
  object.id = id;
}

extension LocalMessageByIndex on IsarCollection<LocalMessage> {
  Future<LocalMessage?> getByMessageId(String messageId) {
    return getByIndex(r'messageId', [messageId]);
  }

  LocalMessage? getByMessageIdSync(String messageId) {
    return getByIndexSync(r'messageId', [messageId]);
  }

  Future<bool> deleteByMessageId(String messageId) {
    return deleteByIndex(r'messageId', [messageId]);
  }

  bool deleteByMessageIdSync(String messageId) {
    return deleteByIndexSync(r'messageId', [messageId]);
  }

  Future<List<LocalMessage?>> getAllByMessageId(List<String> messageIdValues) {
    final values = messageIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'messageId', values);
  }

  List<LocalMessage?> getAllByMessageIdSync(List<String> messageIdValues) {
    final values = messageIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'messageId', values);
  }

  Future<int> deleteAllByMessageId(List<String> messageIdValues) {
    final values = messageIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'messageId', values);
  }

  int deleteAllByMessageIdSync(List<String> messageIdValues) {
    final values = messageIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'messageId', values);
  }

  Future<Id> putByMessageId(LocalMessage object) {
    return putByIndex(r'messageId', object);
  }

  Id putByMessageIdSync(LocalMessage object, {bool saveLinks = true}) {
    return putByIndexSync(r'messageId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByMessageId(List<LocalMessage> objects) {
    return putAllByIndex(r'messageId', objects);
  }

  List<Id> putAllByMessageIdSync(List<LocalMessage> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'messageId', objects, saveLinks: saveLinks);
  }
}

extension LocalMessageQueryWhereSort
    on QueryBuilder<LocalMessage, LocalMessage, QWhere> {
  QueryBuilder<LocalMessage, LocalMessage, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension LocalMessageQueryWhere
    on QueryBuilder<LocalMessage, LocalMessage, QWhereClause> {
  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> messageIdEqualTo(
      String messageId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'messageId',
        value: [messageId],
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause>
      messageIdNotEqualTo(String messageId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'messageId',
              lower: [],
              upper: [messageId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'messageId',
              lower: [messageId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'messageId',
              lower: [messageId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'messageId',
              lower: [],
              upper: [messageId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> matchIdEqualTo(
      String matchId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'matchId',
        value: [matchId],
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> matchIdNotEqualTo(
      String matchId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'matchId',
              lower: [],
              upper: [matchId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'matchId',
              lower: [matchId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'matchId',
              lower: [matchId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'matchId',
              lower: [],
              upper: [matchId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> createdAtEqualTo(
      DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause>
      createdAtNotEqualTo(DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause>
      createdAtGreaterThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [createdAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> createdAtLessThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [],
        upper: [createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterWhereClause> createdAtBetween(
    DateTime lowerCreatedAt,
    DateTime upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lowerCreatedAt],
        includeLower: includeLower,
        upper: [upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension LocalMessageQueryFilter
    on QueryBuilder<LocalMessage, LocalMessage, QFilterCondition> {
  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'encryptedContent',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'encryptedContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'encryptedContent',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'encryptedContent',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      encryptedContentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'encryptedContent',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      hopCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hopCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      hopCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hopCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      hopCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hopCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      hopCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hopCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> isP2pEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isP2p',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      macGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mac',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'mac',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'mac',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> macIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mac',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      macIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'mac',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'matchId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'matchId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'matchId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'matchId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      matchIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'matchId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'messageId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'messageId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'messageId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'messageId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      messageIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'messageId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      nonceGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nonce',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      nonceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'nonce',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition> nonceMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'nonce',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      nonceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nonce',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      nonceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'nonce',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'receiverId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'receiverId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'receiverId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'receiverId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      receiverIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'receiverId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderId',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterFilterCondition>
      senderIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderId',
        value: '',
      ));
    });
  }
}

extension LocalMessageQueryObject
    on QueryBuilder<LocalMessage, LocalMessage, QFilterCondition> {}

extension LocalMessageQueryLinks
    on QueryBuilder<LocalMessage, LocalMessage, QFilterCondition> {}

extension LocalMessageQuerySortBy
    on QueryBuilder<LocalMessage, LocalMessage, QSortBy> {
  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      sortByEncryptedContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedContent', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      sortByEncryptedContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedContent', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByHopCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hopCount', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByHopCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hopCount', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByIsP2p() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isP2p', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByIsP2pDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isP2p', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMac() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mac', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMacDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mac', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMatchId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMatchIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByMessageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByNonce() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nonce', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByNonceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nonce', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortByReceiverId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'receiverId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      sortByReceiverIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'receiverId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortBySenderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> sortBySenderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.desc);
    });
  }
}

extension LocalMessageQuerySortThenBy
    on QueryBuilder<LocalMessage, LocalMessage, QSortThenBy> {
  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      thenByEncryptedContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedContent', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      thenByEncryptedContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedContent', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByHopCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hopCount', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByHopCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hopCount', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByIsP2p() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isP2p', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByIsP2pDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isP2p', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMac() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mac', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMacDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mac', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMatchId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMatchIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByMessageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByNonce() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nonce', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByNonceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nonce', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenByReceiverId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'receiverId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy>
      thenByReceiverIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'receiverId', Sort.desc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenBySenderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.asc);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QAfterSortBy> thenBySenderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.desc);
    });
  }
}

extension LocalMessageQueryWhereDistinct
    on QueryBuilder<LocalMessage, LocalMessage, QDistinct> {
  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct>
      distinctByEncryptedContent({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'encryptedContent',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByHopCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hopCount');
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByIsP2p() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isP2p');
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByMac(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mac', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByMatchId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'matchId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByMessageId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'messageId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByNonce(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nonce', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctByReceiverId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'receiverId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMessage, LocalMessage, QDistinct> distinctBySenderId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderId', caseSensitive: caseSensitive);
    });
  }
}

extension LocalMessageQueryProperty
    on QueryBuilder<LocalMessage, LocalMessage, QQueryProperty> {
  QueryBuilder<LocalMessage, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalMessage, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations>
      encryptedContentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'encryptedContent');
    });
  }

  QueryBuilder<LocalMessage, int, QQueryOperations> hopCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hopCount');
    });
  }

  QueryBuilder<LocalMessage, bool, QQueryOperations> isP2pProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isP2p');
    });
  }

  QueryBuilder<LocalMessage, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> macProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mac');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> matchIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'matchId');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> messageIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'messageId');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> nonceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nonce');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> receiverIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'receiverId');
    });
  }

  QueryBuilder<LocalMessage, String, QQueryOperations> senderIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetMeshRouteCollection on Isar {
  IsarCollection<MeshRoute> get meshRoutes => this.collection();
}

const MeshRouteSchema = CollectionSchema(
  name: r'MeshRoute',
  id: -586046244472644187,
  properties: {
    r'distance': PropertySchema(
      id: 0,
      name: r'distance',
      type: IsarType.long,
    ),
    r'lastUpdate': PropertySchema(
      id: 1,
      name: r'lastUpdate',
      type: IsarType.dateTime,
    ),
    r'nextHopEndpointId': PropertySchema(
      id: 2,
      name: r'nextHopEndpointId',
      type: IsarType.string,
    ),
    r'targetZoneId': PropertySchema(
      id: 3,
      name: r'targetZoneId',
      type: IsarType.string,
    )
  },
  estimateSize: _meshRouteEstimateSize,
  serialize: _meshRouteSerialize,
  deserialize: _meshRouteDeserialize,
  deserializeProp: _meshRouteDeserializeProp,
  idName: r'id',
  indexes: {
    r'targetZoneId': IndexSchema(
      id: -8333002000056131884,
      name: r'targetZoneId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'targetZoneId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'nextHopEndpointId': IndexSchema(
      id: -4868850257256363904,
      name: r'nextHopEndpointId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'nextHopEndpointId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _meshRouteGetId,
  getLinks: _meshRouteGetLinks,
  attach: _meshRouteAttach,
  version: '3.1.0+1',
);

int _meshRouteEstimateSize(
  MeshRoute object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.nextHopEndpointId.length * 3;
  bytesCount += 3 + object.targetZoneId.length * 3;
  return bytesCount;
}

void _meshRouteSerialize(
  MeshRoute object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.distance);
  writer.writeDateTime(offsets[1], object.lastUpdate);
  writer.writeString(offsets[2], object.nextHopEndpointId);
  writer.writeString(offsets[3], object.targetZoneId);
}

MeshRoute _meshRouteDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MeshRoute();
  object.distance = reader.readLong(offsets[0]);
  object.id = id;
  object.lastUpdate = reader.readDateTime(offsets[1]);
  object.nextHopEndpointId = reader.readString(offsets[2]);
  object.targetZoneId = reader.readString(offsets[3]);
  return object;
}

P _meshRouteDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _meshRouteGetId(MeshRoute object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _meshRouteGetLinks(MeshRoute object) {
  return [];
}

void _meshRouteAttach(IsarCollection<dynamic> col, Id id, MeshRoute object) {
  object.id = id;
}

extension MeshRouteByIndex on IsarCollection<MeshRoute> {
  Future<MeshRoute?> getByTargetZoneId(String targetZoneId) {
    return getByIndex(r'targetZoneId', [targetZoneId]);
  }

  MeshRoute? getByTargetZoneIdSync(String targetZoneId) {
    return getByIndexSync(r'targetZoneId', [targetZoneId]);
  }

  Future<bool> deleteByTargetZoneId(String targetZoneId) {
    return deleteByIndex(r'targetZoneId', [targetZoneId]);
  }

  bool deleteByTargetZoneIdSync(String targetZoneId) {
    return deleteByIndexSync(r'targetZoneId', [targetZoneId]);
  }

  Future<List<MeshRoute?>> getAllByTargetZoneId(
      List<String> targetZoneIdValues) {
    final values = targetZoneIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'targetZoneId', values);
  }

  List<MeshRoute?> getAllByTargetZoneIdSync(List<String> targetZoneIdValues) {
    final values = targetZoneIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'targetZoneId', values);
  }

  Future<int> deleteAllByTargetZoneId(List<String> targetZoneIdValues) {
    final values = targetZoneIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'targetZoneId', values);
  }

  int deleteAllByTargetZoneIdSync(List<String> targetZoneIdValues) {
    final values = targetZoneIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'targetZoneId', values);
  }

  Future<Id> putByTargetZoneId(MeshRoute object) {
    return putByIndex(r'targetZoneId', object);
  }

  Id putByTargetZoneIdSync(MeshRoute object, {bool saveLinks = true}) {
    return putByIndexSync(r'targetZoneId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTargetZoneId(List<MeshRoute> objects) {
    return putAllByIndex(r'targetZoneId', objects);
  }

  List<Id> putAllByTargetZoneIdSync(List<MeshRoute> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'targetZoneId', objects, saveLinks: saveLinks);
  }
}

extension MeshRouteQueryWhereSort
    on QueryBuilder<MeshRoute, MeshRoute, QWhere> {
  QueryBuilder<MeshRoute, MeshRoute, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension MeshRouteQueryWhere
    on QueryBuilder<MeshRoute, MeshRoute, QWhereClause> {
  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> targetZoneIdEqualTo(
      String targetZoneId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'targetZoneId',
        value: [targetZoneId],
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause> targetZoneIdNotEqualTo(
      String targetZoneId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetZoneId',
              lower: [],
              upper: [targetZoneId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetZoneId',
              lower: [targetZoneId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetZoneId',
              lower: [targetZoneId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'targetZoneId',
              lower: [],
              upper: [targetZoneId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause>
      nextHopEndpointIdEqualTo(String nextHopEndpointId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'nextHopEndpointId',
        value: [nextHopEndpointId],
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterWhereClause>
      nextHopEndpointIdNotEqualTo(String nextHopEndpointId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'nextHopEndpointId',
              lower: [],
              upper: [nextHopEndpointId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'nextHopEndpointId',
              lower: [nextHopEndpointId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'nextHopEndpointId',
              lower: [nextHopEndpointId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'nextHopEndpointId',
              lower: [],
              upper: [nextHopEndpointId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension MeshRouteQueryFilter
    on QueryBuilder<MeshRoute, MeshRoute, QFilterCondition> {
  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> distanceEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'distance',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> distanceGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'distance',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> distanceLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'distance',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> distanceBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'distance',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> lastUpdateEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastUpdate',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      lastUpdateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastUpdate',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> lastUpdateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastUpdate',
        value: value,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> lastUpdateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastUpdate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nextHopEndpointId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'nextHopEndpointId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'nextHopEndpointId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nextHopEndpointId',
        value: '',
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      nextHopEndpointIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'nextHopEndpointId',
        value: '',
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> targetZoneIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> targetZoneIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'targetZoneId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'targetZoneId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition> targetZoneIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'targetZoneId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetZoneId',
        value: '',
      ));
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterFilterCondition>
      targetZoneIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'targetZoneId',
        value: '',
      ));
    });
  }
}

extension MeshRouteQueryObject
    on QueryBuilder<MeshRoute, MeshRoute, QFilterCondition> {}

extension MeshRouteQueryLinks
    on QueryBuilder<MeshRoute, MeshRoute, QFilterCondition> {}

extension MeshRouteQuerySortBy on QueryBuilder<MeshRoute, MeshRoute, QSortBy> {
  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByDistance() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'distance', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByDistanceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'distance', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByLastUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdate', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByLastUpdateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdate', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByNextHopEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextHopEndpointId', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy>
      sortByNextHopEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextHopEndpointId', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByTargetZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetZoneId', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> sortByTargetZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetZoneId', Sort.desc);
    });
  }
}

extension MeshRouteQuerySortThenBy
    on QueryBuilder<MeshRoute, MeshRoute, QSortThenBy> {
  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByDistance() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'distance', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByDistanceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'distance', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByLastUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdate', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByLastUpdateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdate', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByNextHopEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextHopEndpointId', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy>
      thenByNextHopEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextHopEndpointId', Sort.desc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByTargetZoneId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetZoneId', Sort.asc);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QAfterSortBy> thenByTargetZoneIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetZoneId', Sort.desc);
    });
  }
}

extension MeshRouteQueryWhereDistinct
    on QueryBuilder<MeshRoute, MeshRoute, QDistinct> {
  QueryBuilder<MeshRoute, MeshRoute, QDistinct> distinctByDistance() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'distance');
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QDistinct> distinctByLastUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastUpdate');
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QDistinct> distinctByNextHopEndpointId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nextHopEndpointId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MeshRoute, MeshRoute, QDistinct> distinctByTargetZoneId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetZoneId', caseSensitive: caseSensitive);
    });
  }
}

extension MeshRouteQueryProperty
    on QueryBuilder<MeshRoute, MeshRoute, QQueryProperty> {
  QueryBuilder<MeshRoute, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MeshRoute, int, QQueryOperations> distanceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'distance');
    });
  }

  QueryBuilder<MeshRoute, DateTime, QQueryOperations> lastUpdateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastUpdate');
    });
  }

  QueryBuilder<MeshRoute, String, QQueryOperations>
      nextHopEndpointIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nextHopEndpointId');
    });
  }

  QueryBuilder<MeshRoute, String, QQueryOperations> targetZoneIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetZoneId');
    });
  }
}
