CharInfo :: struct { // @fixme Also store how many bytes it is worth.
    // Original glyph info, where the vertices should be
    // without special placement.
    glyphBlank : bool;
    glyphOffset : Chamber.vec2;
    glyphExtent : Chamber.vec2;
    glyphAdvance : float;

    effective : struct {
        glyphOffset : Chamber.vec2;
        xStart : float;
        xEnd : float;
        y : float;
    }
}

create_text_mesh :: () -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);
    mesh.material = Magma.create_material(instance.shaders.text);
    return mesh;
}

text_mesh_update :: (mesh : *Magma.Mesh, text : string, font : *Chamber.Font, color : Chamber.vec3) -> []CharInfo #must {
    using *instance.list;

    mesh.disabled = (text.count == 0);
    if mesh.disabled then return .[];

    // @todo Have a clever way to keep the texture up-to-date.
    // And not recreate it each time...
    glyphInfos := Chamber.font_glyph_infos(font, text); // @todo Get them without the blanks characters.
    defer Basic.array_free(glyphInfos);
    fontTexture := Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(fontTexture, font.pixels, font.extent);

    Magma.material_set(mesh.material, "fontTexture", fontTexture);
    Magma.material_set(mesh.material, "color", color);

    charInfos : [..]CharInfo;
    Basic.array_resize(*charInfos, glyphInfos.count);

    totalBlanks := 0;

    for *glyphInfo, index : glyphInfos {
        if glyphInfo.blank then totalBlanks += 1;
        charInfos[index].glyphBlank = glyphInfo.blank;
        charInfos[index].glyphOffset = glyphInfo.offset;
        charInfos[index].glyphExtent = glyphInfo.extent;
        charInfos[index].glyphAdvance = glyphInfo.advance;
    }

    // @todo Is baking all that into one texture worth it?
    Basic.array_resize(*mesh.vertices, 4 * (glyphInfos.count - totalBlanks));
    Basic.array_resize(*mesh.indices, 6 * (glyphInfos.count - totalBlanks));

    index := 0;
    for *glyphInfo : glyphInfos {
        if glyphInfo.blank then continue;

        mesh.vertices[4 * index + 0].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 0].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 1].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 1].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 2].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 2].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 3].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 3].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 0].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 0].uv.y = glyphInfo.minUv.y;
        mesh.vertices[4 * index + 1].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 1].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 2].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 2].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 3].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 3].uv.y = glyphInfo.minUv.y;

        mesh.indices[6 * index + 0] = cast(u16) (4 * index + 0);
        mesh.indices[6 * index + 1] = cast(u16) (4 * index + 1);
        mesh.indices[6 * index + 2] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 3] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 4] = cast(u16) (4 * index + 3);
        mesh.indices[6 * index + 5] = cast(u16) (4 * index + 0);

        index += 1;
    }

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);
    Magma.mesh_commit_instance(mesh);

    return charInfos;
}
