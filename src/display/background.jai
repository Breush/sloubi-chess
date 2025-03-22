BackgroundEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;
}

background_create :: () -> *BackgroundEntity {
    using background := SillMeta.create_background_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);

    primitive := create_rect_mesh(anchor = .TopLeft);
    primitive.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(primitive.material, "color", instance.config.env.backgroundColor);

    node := Basic.array_add(*mesh.nodes);
    Basic.array_add(*node.primitives, primitive);

    // Sill.transform_rotate(*transform, Math.PI / 2, .{0, 1, 0});
    transform.translation.z = UiConstants.DepthBackground;
    Sill.transform_commit(*transform);

    return background;
}

#scope_file

_on_message :: (background : *BackgroundEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(background);
    }
}

_reflow :: (using background : *BackgroundEntity) {
    extent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);
    mesh.nodes[0].transform.scaling.xy = extent;
    Sill.mesh_commit_nodes(*mesh, instantly = true);
}
