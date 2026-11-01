[English](0001-shader-file-effects.md) | [日本語](0001-shader-file-effects.ja.md)

# Effects and Generators are extended with a shader file plus a declaration file

An Effect or Generator is added by dropping a Metal shader (`.metal`) and a parameter declaration (JSON or similar) into a folder. No rebuild of the app is needed, and hot-reload works during a show. We prioritized fast tweaking before a show and avoiding a live accident from a failed build.

## Considered Options

- **Swift protocol-conforming plugins**: type-safe and a good fit for complex multi-pass or stateful processing, but every addition needs a rebuild and hot-reload is not possible.
- **Dynamically loaded bundles (.bundle)**: no rebuild, but signing and loading are heavy to manage, which is overkill for a personal tool.

## Consequences

- Effects that need multiple passes or state across frames are hard to express with a shader plus a declaration file alone. If that becomes necessary we will consider adding the Swift plugin route.
- The declaration file format becomes the public interface of an Effect, so it will be hard to change later.
