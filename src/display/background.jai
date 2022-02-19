Background :: struct {
    shader : *Magma.Shader;
    mesh : *Magma.Mesh;
}

background_init :: () {
    using *instance.background;

    shader = Magma.create_shader(instance.renderer, "./assets/materials/background");
    mesh = Magma.create_mesh(instance.renderScene);
    mesh.material = Magma.create_material(shader);

    extent := Crater.window_get_extent(instance.window);

    positions := Chamber.vec3.[
        .{-0.5, -0.5, 0. },
        .{-0.5,  0.5, 0. },
        .{ 0.5,  0.5, 0. },
        .{ 0.5, -0.5, 0. },
    ];

    indices := u16.[0,  1,  2,  2,  3,  0];

    Basic.array_resize(*mesh.vertices, positions.count);
    for *vertex, i : mesh.vertices {
        vertex.position = positions[i];
    }

    Basic.array_resize(*mesh.indices, indices.count);
    memcpy(mesh.indices.data, indices.data, size_of(u16) * indices.count);

    mesh.translation.z = 90; // Far, far away.
    mesh.scaling.x = cast(float) extent.width;
    mesh.scaling.y = cast(float) extent.height;

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);
    Magma.mesh_commit_instance(mesh);
}
