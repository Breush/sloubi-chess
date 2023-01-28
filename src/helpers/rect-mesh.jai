create_rect_mesh :: (width := 1.0, height := 1.0, depth := 0.0, anchor := Chamber.Anchor.Center, existingMesh : *Magma.Mesh = null) -> *Magma.Mesh {
    mesh := existingMesh;
    if mesh == null {
        mesh = Magma.create_mesh(instance.engine.scene);
    }

    positions : [4]Chamber.vec3 = ---;

    positions[0].x = -width / 2.0;
    positions[0].y = -height / 2.0;
    positions[0].z = depth;
    positions[1].x = -width / 2.0;
    positions[1].y = height / 2.0;
    positions[1].z = depth;
    positions[2].x = width / 2.0;
    positions[2].y = height / 2.0;
    positions[2].z = depth;
    positions[3].x = width / 2.0;
    positions[3].y = -height / 2.0;
    positions[3].z = depth;

    uvs := Chamber.vec2.[
        .{ 0.,  0. },
        .{ 0.,  1. },
        .{ 1.,  1. },
        .{ 1.,  0. },
    ];

    indices := u16.[0,  1,  2,  2,  3,  0];

    offset : Chamber.vec3;
    if anchor == {
        case .Left;         offset.x += width / 2.0;
        case .Right;        offset.x -= width / 2.0;
        case .Top;          offset.y += height / 2.0;
        case .Bottom;       offset.y -= height / 2.0;
        case .TopLeft;      offset.x += width / 2.0; offset.y += height / 2.0;
        case .TopRight;     offset.x -= width / 2.0; offset.y += height / 2.0;
        case .BottomLeft;   offset.x += width / 2.0; offset.y -= height / 2.0;
        case .BottomRight;  offset.x -= width / 2.0; offset.y -= height / 2.0;
    }

    Basic.array_resize(*mesh.vertices, positions.count);
    for *vertex, i : mesh.vertices {
        vertex.position.std = positions[i] + offset;
        vertex.uv = uvs[i];
    }

    Basic.array_resize(*mesh.indices, indices.count);
    memcpy(mesh.indices.data, indices.data, size_of(u16) * indices.count);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}