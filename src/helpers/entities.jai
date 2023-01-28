TransformEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage;

    transform : Sill.TransformComponent;
}

MeshEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

InvisibleUiEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    ui : Sill.UiComponent;
}

UiEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
}

UiButtonEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
    button : ButtonComponent;
}
