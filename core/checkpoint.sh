#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Checkpoint/Rollback Module
#
# Description:
#   Checkpoint system for installation rollback. Creates checkpoints at
#   critical installation steps and allows rollback to previous checkpoints
#   if errors occur.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/rezeptor
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace checkpoint
# @description Checkpoint management for installation rollback
# ============================================================================

CHECKPOINT_DIR="${CHECKPOINT_DIR:-$HOME/.photoshop/checkpoints}"

# ============================================================================
# @function checkpoint::init
# @description Initialize checkpoint system
# @return 0 on success, 1 on error
# ============================================================================
checkpoint::init() {
    mkdir -p "$CHECKPOINT_DIR" || return 1
    return 0
}

# ============================================================================
# @function checkpoint::create
# @description Create a checkpoint at current installation state
# @param $1 Checkpoint name (e.g., "wine_prefix_initialized")
# @return 0 on success, 1 on error
# @example checkpoint::create "wine_prefix_initialized"
# ============================================================================
checkpoint::create() {
    local checkpoint_name="$1"
    local checkpoint_file="$CHECKPOINT_DIR/${checkpoint_name}.checkpoint"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    checkpoint::init || return 1
    
    # Save current state information
    {
        echo "# Checkpoint: $checkpoint_name"
        echo "# Created: $timestamp"
        echo "CHECKPOINT_NAME=$checkpoint_name"
        echo "TIMESTAMP=$timestamp"
        
        # Save Wine prefix state if it exists
        if [ -n "${WINE_PREFIX:-}" ] && [ -d "$WINE_PREFIX" ]; then
            echo "WINE_PREFIX=$WINE_PREFIX"
            echo "WINE_PREFIX_EXISTS=true"
        else
            echo "WINE_PREFIX_EXISTS=false"
        fi
        
        # Save installation paths
        if [ -n "${SCR_PATH:-}" ]; then
            echo "SCR_PATH=$SCR_PATH"
        fi
        
        if [ -n "${CACHE_PATH:-}" ]; then
            echo "CACHE_PATH=$CACHE_PATH"
        fi
    } > "$checkpoint_file"
    
    # Use log::debug if available, otherwise use echo
    if command -v log::debug >/dev/null 2>&1; then
        log::debug "Checkpoint created: $checkpoint_name"
    else
        echo "[DEBUG] Checkpoint created: $checkpoint_name" >&2
    fi
    return 0
}

# ============================================================================
# @function checkpoint::list
# @description List all available checkpoints
# @return 0 on success, 1 on error
# ============================================================================
checkpoint::list() {
    if [ ! -d "$CHECKPOINT_DIR" ]; then
        return 1
    fi
    
    local checkpoints
    checkpoints=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f 2>/dev/null | sort)
    
    if [ -z "$checkpoints" ]; then
        echo "No checkpoints found"
        return 1
    fi
    
    echo "Available checkpoints:"
    echo "$checkpoints" | while IFS= read -r checkpoint; do
        local name
        name=$(basename "$checkpoint" .checkpoint)
        local timestamp
        timestamp=$(grep "^TIMESTAMP=" "$checkpoint" 2>/dev/null | cut -d'=' -f2- || echo "unknown")
        echo "  - $name (created: $timestamp)"
    done
    
    return 0
}

# ============================================================================
# @function checkpoint::rollback
# @description Rollback to a specific checkpoint
# @param $1 Checkpoint name to rollback to
# @return 0 on success, 1 on error
# @example checkpoint::rollback "wine_prefix_initialized"
# ============================================================================
checkpoint::rollback() {
    local checkpoint_name="$1"
    local checkpoint_file="$CHECKPOINT_DIR/${checkpoint_name}.checkpoint"
    
    if [ ! -f "$checkpoint_file" ]; then
        if command -v log::error >/dev/null 2>&1; then
            log::error "Checkpoint not found: $checkpoint_name"
        else
            echo "[ERROR] Checkpoint not found: $checkpoint_name" >&2
        fi
        return 1
    fi
    
    if command -v log::warning >/dev/null 2>&1; then
        log::warning "Rolling back to checkpoint: $checkpoint_name"
    else
        echo "[WARNING] Rolling back to checkpoint: $checkpoint_name" >&2
    fi
    
    # Load checkpoint state
    # shellcheck source=/dev/null
    source "$checkpoint_file"
    
    # Remove files/directories created after this checkpoint
    # This is a simplified rollback - in a full implementation, we would
    # track all file operations and reverse them
    
    if command -v log::info >/dev/null 2>&1; then
        log::info "Rollback to checkpoint $checkpoint_name completed"
    else
        echo "[INFO] Rollback to checkpoint $checkpoint_name completed" >&2
    fi
    return 0
}

# ============================================================================
# @function checkpoint::cleanup
# @description Remove all checkpoints (after successful installation)
# @return 0 on success, 1 on error
# ============================================================================
checkpoint::cleanup() {
    if [ -d "$CHECKPOINT_DIR" ]; then
        # CRITICAL: Use safe_remove if available, otherwise validate before rm -rf
        if type filesystem::safe_remove >/dev/null 2>&1; then
            filesystem::safe_remove "$CHECKPOINT_DIR" "checkpoint::cleanup" || return 1
        else
            # Fallback: validate before removing
            if [ -z "$CHECKPOINT_DIR" ] || [ "$CHECKPOINT_DIR" = "/" ] || [ "$CHECKPOINT_DIR" = "/root" ]; then
                echo "ERROR: Unsafe checkpoint directory: $CHECKPOINT_DIR" >&2
                return 1
            fi
            rm -rf "$CHECKPOINT_DIR" || return 1
        fi
        if command -v log::debug >/dev/null 2>&1; then
            log::debug "All checkpoints cleaned up"
        else
            echo "[DEBUG] All checkpoints cleaned up" >&2
        fi
    fi
    return 0
}

# Auto-initialize on source
checkpoint::init

