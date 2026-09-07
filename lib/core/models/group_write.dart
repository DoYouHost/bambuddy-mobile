/// Body for `POST /groups/` (`backend/app/schemas/group.py::GroupCreate`). A
/// group created from here is never a system group — the server sets
/// `is_system: false` itself
/// (`backend/app/api/routes/groups.py::create_group`).
class GroupCreateInput {
  const GroupCreateInput({
    required this.name,
    this.description,
    this.permissions = const [],
  });

  final String name;
  final String? description;
  final List<String> permissions;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'permissions': permissions,
  };
}

/// Body for `PATCH /groups/{id}` (`backend/app/schemas/group.py::GroupUpdate`).
///
/// Omitted means unchanged, as everywhere else on this server. [permissions]
/// **replaces** the set rather than adding to it (`groups.py::update_group`),
/// so a caller sending it must send the whole set — including the ones its
/// editor chose not to show.
class GroupUpdateInput {
  const GroupUpdateInput({this.name, this.description, this.permissions});

  final String? name;
  final String? description;
  final List<String>? permissions;

  bool get isEmpty =>
      name == null && description == null && permissions == null;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (permissions != null) 'permissions': permissions,
  };
}
