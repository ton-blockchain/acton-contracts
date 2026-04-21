import "@acton/env"

fun envOr<T>(name: string, default: T): T {
    return env<T>(name) ?? default;
}
