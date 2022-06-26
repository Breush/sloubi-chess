// A downwards arrow (y positive).
create_arrow_mesh :: (length := 1.0, thickness := 0.2, basePadding := 0.0, headPadding := 0.0, depth := 0.0, existingMesh : *Magma.Mesh = null) -> *Magma.Mesh {
    mesh := existingMesh;
    if mesh == null {
        mesh = Magma.create_mesh(instance.engine.scene);
    }

    positions : [7]Chamber.vec3 = ---;

    effectiveLength := length - basePadding - headPadding;
    headHeight := thickness;

    // Base
    positions[0].x = -thickness / 2.0;
    positions[0].y = basePadding;
    positions[0].z = depth;
    positions[1].x = -thickness / 2.0;
    positions[1].y = basePadding + effectiveLength - headHeight;
    positions[1].z = depth;
    positions[2].x = thickness / 2.0;
    positions[2].y = basePadding + effectiveLength - headHeight;
    positions[2].z = depth;
    positions[3].x = thickness / 2.0;
    positions[3].y = basePadding;
    positions[3].z = depth;
    // Head
    positions[4].x = -0.75 * thickness;
    positions[4].y = basePadding + effectiveLength - headHeight;
    positions[4].z = depth;
    positions[5].x = 0.0;
    positions[5].y = basePadding + effectiveLength;
    positions[5].z = depth;
    positions[6].x = 0.75 * thickness;
    positions[6].y = basePadding + effectiveLength - headHeight;
    positions[6].z = depth;

    indices := u16.[0, 1, 2, 2, 3, 0, 4, 5, 6];

    Basic.array_resize(*mesh.vertices, positions.count);
    for *vertex, i : mesh.vertices {
        vertex.position = positions[i];
    }

    Basic.array_resize(*mesh.indices, indices.count);
    memcpy(mesh.indices.data, indices.data, size_of(u16) * indices.count);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}