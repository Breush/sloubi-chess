LabelEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
}

create_label :: (text := "Label", style := "mainLight", anchor := Chamber.Anchor.Center) -> *LabelEntity {
    label := SillMeta.create_label_entity(instance.engine);
    label.ui.disabled = true;

    // Text.
    textMesh, textMeshNode := Sill.mesh_make_primitive(*label.mesh);
    create_text_mesh(existingMesh = textMesh);

    textWidth, charInfos := text_mesh_update(textMesh, text, style, instance.config.env.textColor, anchor = anchor, computeCharInfos = true);
    defer Basic.array_free(charInfos.infos);
    justify_char_infos(*charInfos, UiConstants.WidthLabel, 0.0);
    minBounds, maxBounds := place_from_char_infos(textMesh, *charInfos, anchor);

    label.ui.extent.std = maxBounds - minBounds;
    label.ui.anchor = anchor;

    return label;
}
