#!/bin/bash
# ABOUTME: Automated Docker image build script for Magnet IRC Network containers
# ABOUTME: Builds Solanum and Atheme images with OpenSSL optimization for AMD EPYC

set -e

# Configuration
REGISTRY=${REGISTRY:-""}
TAG=${TAG:-"latest"}
PLATFORM=${PLATFORM:-"linux/amd64"}
CACHE=${CACHE:-"true"}

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker version >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_info "Docker is available and running"
}

build_image() {
    local dockerfile=$1
    local image_name=$2
    local full_tag="${REGISTRY}${image_name}:${TAG}"
    
    log_info "Building ${image_name} from ${dockerfile}"
    
    # Build arguments
    local build_args=""
    if [ "$CACHE" = "false" ]; then
        build_args="--no-cache"
    fi
    
    # Build command
    docker build \
        $build_args \
        --platform $PLATFORM \
        --file $dockerfile \
        --tag $full_tag \
        .
    
    if [ $? -eq 0 ]; then
        log_info "Successfully built ${full_tag}"
        
        # Show image info
        docker images $full_tag
        
        return 0
    else
        log_error "Failed to build ${full_tag}"
        return 1
    fi
}

validate_files() {
    local required_files=(
        "Dockerfile.solanum"
        "Dockerfile.atheme"
        "ircd.conf.template"
        "atheme.conf.template"
        "start-solanum.sh"
        "start-atheme.sh"
    )
    
    log_info "Validating required files..."
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file missing: $file"
            exit 1
        fi
    done
    
    # Check executable permissions on scripts
    if [ ! -x "start-solanum.sh" ]; then
        log_warn "start-solanum.sh is not executable, fixing..."
        chmod +x start-solanum.sh
    fi
    
    if [ ! -x "start-atheme.sh" ]; then
        log_warn "start-atheme.sh is not executable, fixing..."
        chmod +x start-atheme.sh
    fi
    
    log_info "All required files present and valid"
}

show_usage() {
    cat << EOF
build-images.sh - Build Magnet IRC Network Docker Images

Usage:
    build-images.sh [OPTIONS] [IMAGE]

Options:
    --registry REGISTRY     Set registry prefix (default: none)
    --tag TAG              Set image tag (default: latest)  
    --platform PLATFORM    Set target platform (default: linux/amd64)
    --no-cache             Disable build cache
    --help                 Show this help message

Images:
    solanum                Build Solanum IRCd image only
    atheme                 Build Atheme services image only  
    all                    Build all images (default)

Examples:
    # Build all images
    build-images.sh
    
    # Build with custom tag
    build-images.sh --tag v1.0.0
    
    # Build for registry
    build-images.sh --registry myregistry.com/ --tag latest
    
    # Build specific image
    build-images.sh solanum
    
    # Build without cache
    build-images.sh --no-cache all

Environment Variables:
    REGISTRY               Registry prefix for images
    TAG                    Image tag to use  
    PLATFORM               Target platform
    CACHE                  Enable/disable cache (true/false)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --no-cache)
            CACHE="false"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        solanum|atheme|all)
            TARGET="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set default target
TARGET=${TARGET:-"all"}

# Main execution
main() {
    log_info "Starting Magnet IRC Network image build process"
    log_info "Registry: ${REGISTRY:-none}"
    log_info "Tag: $TAG"
    log_info "Platform: $PLATFORM" 
    log_info "Cache: $CACHE"
    log_info "Target: $TARGET"
    
    check_docker
    validate_files
    
    local build_start=$(date +%s)
    local failed_builds=()
    
    case $TARGET in
        "solanum")
            build_image "Dockerfile.solanum" "magnet-solanum" || failed_builds+=("solanum")
            ;;
        "atheme")
            build_image "Dockerfile.atheme" "magnet-atheme" || failed_builds+=("atheme")
            ;;
        "all")
            build_image "Dockerfile.solanum" "magnet-solanum" || failed_builds+=("solanum")
            build_image "Dockerfile.atheme" "magnet-atheme" || failed_builds+=("atheme")
            ;;
    esac
    
    local build_end=$(date +%s)
    local build_duration=$((build_end - build_start))
    
    log_info "Build process completed in ${build_duration} seconds"
    
    # Report results
    if [ ${#failed_builds[@]} -eq 0 ]; then
        log_info "All builds successful!"
        
        # Show final image list
        echo
        log_info "Built images:"
        if [ "$TARGET" = "all" ] || [ "$TARGET" = "solanum" ]; then
            docker images "${REGISTRY}magnet-solanum:${TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
        fi
        if [ "$TARGET" = "all" ] || [ "$TARGET" = "atheme" ]; then
            docker images "${REGISTRY}magnet-atheme:${TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
        fi
        
        exit 0
    else
        log_error "Failed builds: ${failed_builds[*]}"
        exit 1
    fi
}

# Run main function
main