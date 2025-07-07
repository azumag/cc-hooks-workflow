# Hooks Management Strategy

## File Structure
```
hooks/
├── ci-monitor-hook.sh      # Master version
├── review-complete-hook.sh
├── stop-hook.sh
└── shared-utils.sh

hooks_old/
├── ci-monitor-hook.sh -> ../hooks/ci-monitor-hook.sh  # Symbolic link
└── (other legacy hooks for reference)
```

## Design Principles Applied

### DRY (Don't Repeat Yourself)
- **Issue**: Previously had duplicate ci-monitor-hook.sh in both hooks/ and hooks_old/
- **Solution**: Use symbolic link from hooks_old/ to hooks/ to maintain single source of truth
- **Benefit**: Only one file to maintain, automatic consistency

### KISS (Keep It Simple, Stupid)  
- **Issue**: File copying created maintenance complexity
- **Solution**: Simple symbolic link maintains compatibility without duplication
- **Benefit**: Clear reference hierarchy, reduced complexity

### YAGNI (You Ain't Gonna Need It)
- **Assessment**: hooks_old/ compatibility needed for existing Claude Code configurations
- **Solution**: Minimal intervention via symbolic link rather than complex migration
- **Future**: Plan to update Claude Code configurations to use hooks/ directly

## Maintenance Notes

1. **Primary development**: Always update files in `hooks/` directory
2. **Legacy support**: `hooks_old/ci-monitor-hook.sh` automatically reflects changes via symlink
3. **Testing**: Both paths (`hooks/` and `hooks_old/`) reference the same implementation
4. **Migration path**: Eventually update all Claude Code configurations to use `hooks/` directly

## Verification
```bash
# Both paths should show identical content
diff hooks/ci-monitor-hook.sh hooks_old/ci-monitor-hook.sh
# (No output = identical)

# Both paths should work
echo '{}' | hooks/ci-monitor-hook.sh
echo '{}' | hooks_old/ci-monitor-hook.sh
```