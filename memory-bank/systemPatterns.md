# System Patterns *Optional*

This file documents recurring patterns and standards used in the project.
It is optional, but recommended to be updated as the project evolves.
2025-07-30 10:12:10 - Log of updates made.

*

## Coding Patterns

*   

## Architectural Patterns

*   

## Testing Patterns

*
  
### Docker Security Patterns  
- **Immutable Tags**: Always pin to explicit version (e.g. `24.04.0-py3`)  
- **Core Dump Prevention**: Set `ulimit -c 0` in Dockerfile and shell profiles  
- **Layered Cleanup**: Chain `apt-get` operations in single RUN statement  
- **Retry Logic**: Implement exponential backoff for external API calls  