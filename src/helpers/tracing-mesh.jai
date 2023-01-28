
// A tracing mesh is a "elongated" rect mesh.
// For instance:
// *-----*
// |      \
// |       \
// *        \
//  \        *
//   \       |
//    \      |
//     *-----*
// It is of base size 1, and is used to show a movement of a piece
// from a square to another, with the shape overlapping both the source and
// the target squares.
create_tracing_mesh :: (xDisplacement : float, yDisplacement : float) -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);

    positions : []Chamber.vec3;
    uvs : []Chamber.vec2;
    altUvs : []Chamber.vec2;
    indices : []u16;

    displacedPositionIndices : []s64;

    // We have 8 cases, it's easier to just hardcode a lot, than trying to be too clever.
    if xDisplacement == 0 || yDisplacement == 0 {
        positions = Chamber.vec3.[.{-0.5, -0.5, 0.0}, .{-0.5, 0.5, 0.0}, .{0.5, 0.5, 0.0}, .{0.5, -0.5, 0.0}];
        uvs       = Chamber.vec2.[.{0.0, 0.0}, .{0.0, 1.0}, .{1.0, 1.0}, .{1.0, 0.0}];
        indices   = u16.[0, 1, 2, 2, 3, 0];
    } else if xDisplacement > 0 && yDisplacement > 0 || xDisplacement < 0 && yDisplacement < 0 {
        positions = Chamber.vec3.[.{-0.5, -0.5, 0.0}, .{-0.5, 0.5, 0.0}, .{ 0.5, -0.5, 0.0}, .{-0.5, 0.5, 0.0}, .{ 0.5, 0.5, 0.0}, .{ 0.5, -0.5, 0.0}];
        uvs       = Chamber.vec2.[.{0.0, 0.0}, .{0.0, 1.0}, .{1.0, 0.0}, .{0.0, 1.0}, .{1.0, 1.0}, .{1.0, 0.0}];
        indices   = u16.[0, 1, 2, 1, 3, 5, 5, 2, 1, 3, 4, 5];
    } else {
        positions = Chamber.vec3.[.{-0.5, 0.5, 0.0}, .{ 0.5, 0.5, 0.0}, .{-0.5, -0.5, 0.0}, .{ 0.5, 0.5, 0.0}, .{ 0.5, -0.5, 0.0}, .{-0.5, -0.5, 0.0}];
        uvs       = Chamber.vec2.[.{0.0, 1.0}, .{1.0, 1.0}, .{0.0, 0.0}, .{1.0, 1.0}, .{1.0, 0.0}, .{0.0, 0.0}];
        indices   = u16.[0, 1, 2, 1, 3, 5, 5, 2, 1, 3, 4, 5];
    }

    // X == 0 || Y == 0
    if xDisplacement == 0 && yDisplacement > 0 {
        displacedPositionIndices = s64.[1, 2];
        altUvs = Chamber.vec2.[.{0.0, -1.0}, .{1.0, -1.0}, .{1.0, 1.0}, .{0.0, 1.0}];
    } else if xDisplacement == 0 && yDisplacement < 0 {
        displacedPositionIndices = s64.[0, 3];
        altUvs = Chamber.vec2.[.{1.0, -1.0}, .{0.0, -1.0}, .{0.0, 1.0}, .{1.0, 1.0}];
    } else if xDisplacement > 0 && yDisplacement == 0 {
        displacedPositionIndices = s64.[2, 3];
        altUvs = Chamber.vec2.[.{0.0, -1.0}, .{0.0, 1.0}, .{1.0, 1.0}, .{1.0, -1.0}];
    } else if xDisplacement < 0 && yDisplacement == 0 {
        displacedPositionIndices = s64.[0, 1];
        altUvs = Chamber.vec2.[.{1.0, -1.0}, .{1.0, 1.0}, .{0.0, 1.0}, .{0.0, -1.0}];
    }

    // X > 0 and X < 0
    else if xDisplacement > 0 {
        displacedPositionIndices = s64.[3, 4, 5];
        altUvs = Chamber.vec2.[.{0.0,  0.0}, .{0.0, -1.0}, .{0.0, 1.0}, .{1.0, -1.0}, .{1.0,  0.0}, .{1.0, 1.0}];
    } else if xDisplacement < 0 {
        displacedPositionIndices = s64.[0, 1, 2];
        altUvs = Chamber.vec2.[.{1.0,  0.0}, .{1.0, -1.0}, .{1.0, 1.0}, .{0.0, -1.0}, .{0.0,  0.0}, .{0.0, 1.0}];
    }

    Basic.array_resize(*mesh.vertices, positions.count);
    for *vertex, i : mesh.vertices {
        vertex.position = positions[i];
        vertex.normal.xy = altUvs[i];
        vertex.uv = uvs[i];

        if Basic.array_find(displacedPositionIndices, i) {
            vertex.position.x += xDisplacement;
            vertex.position.y += yDisplacement;
        } else {
            vertex.uv.x -= xDisplacement;
            vertex.uv.y -= yDisplacement;
        }
    }

    if altUvs.count == 6 {
        theta := Math.atan2(yDisplacement, xDisplacement);
        cosTheta := Math.abs(Math.cos(theta));
        sinTheta := Math.abs(Math.sin(theta));
        if xDisplacement > 0 {
            mesh.vertices[1].normal.x += sinTheta;
            mesh.vertices[2].normal.x += cosTheta;
            mesh.vertices[3].normal.x -= cosTheta;
            mesh.vertices[5].normal.x -= sinTheta;
        } else {
            mesh.vertices[1].normal.x -= sinTheta;
            mesh.vertices[2].normal.x -= cosTheta;
            mesh.vertices[3].normal.x += cosTheta;
            mesh.vertices[5].normal.x += sinTheta;
        }
    }

    Basic.array_resize(*mesh.indices, indices.count);
    memcpy(mesh.indices.data, indices.data, size_of(u16) * indices.count);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}