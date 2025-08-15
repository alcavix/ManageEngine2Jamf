#!/bin/bash

################################################################################
# HOW TO DEPLOY AND RUN THIS SCRIPT REMOTELY
#	
#   Project:      Migrate-me2jamf
#   Version:      1.0.3
#   Author:       Tomer Alcavi
#   GitHub:       https://github.com/alcavix
#   Project Link: https://github.com/alcavix/Migrate-me2jamf
#   License:      MIT
#
#  If you find this project useful, drop a star or fork!
#  Questions or ideas? Open an issue on the project’s GitHub page!
#  Please keep this little credit line. It means a lot for the open-source spirit :)
#  Grateful for the open-source community and spirit that inspires projects like this.
#
# 1. Place this script on the target Mac (Manual Method):
#    - Copy this script to a location like `/usr/local/bin/Migrate-ManageEngine2Jamf.sh`
#      or `/Library/Scripts/Migrate-ManageEngine2Jamf.sh`.
#
# 2. Make the script executable on the target Mac (Manual Method):
#    - Open Terminal on the target Mac and run:
#      `sudo chmod +x /path/to/Migrate-ManageEngine2Jamf.sh`
#      (e.g., `sudo chmod +x /usr/local/bin/Migrate-ManageEngine2Jamf.sh`)
#
# 3. Run remotely:
#    a. Using SSH (if script is already on the Mac):
#       - Ensure SSH is enabled on the target Mac (System Settings > General > Sharing > Remote Login).
#       - From another machine, use an SSH command:
#         `ssh your_username@target_mac_ip_or_hostname 'sudo /path/to/Migrate-ManageEngine2Jamf.sh'`
#         Example: `ssh adminuser@192.168.1.10 'sudo /usr/local/bin/Migrate-ManageEngine2Jamf.sh'`
#       - You will be prompted for the password for 'your_username' on the target Mac.
#
#    b. Using curl to download and execute (Script must be hosted online):
#       - Host this script file (Migrate-ManageEngine2Jamf.sh) on a web server or a service
#         like GitHub Gist (use the "Raw" file URL).
#       - From the target Mac's terminal, or via SSH, run:
#         `curl -sSL https://your-script-host.com/path/to/Migrate-ManageEngine2Jamf.sh | sudo bash`
#       - Example with a placeholder URL:
#         `curl -sSL https://gist.githubusercontent.com/youruser/yourgistid/raw/Migrate-ManageEngine2Jamf.sh | sudo bash`
#       - IMPORTANT: Review the script from the URL before running it this way to ensure it's what you expect.
#         Piping curl to sudo bash executes the script with root privileges immediately.
#
# 4. Logging:
#    - The script logs its output to `/var/log/mdm_migration.log` on the target Mac
#      and also prints to stdout (which will be visible in your SSH session or terminal).
#
################################################################################

clear

# Enable strict mode
set -u
set -o pipefail

################################################################################
# Script for Migrating from ManageEngine MDM to Jamf MDM
#
# This script performs the following actions:
# 1. Removes the device from ManageEngine MDM via API.
# 2. Validates that ManageEngine MDM profiles have been removed.
# 3. Uninstalls the ManageEngine agent if profiles are removed.
# 4. Sets a preference to skip the Jamf Self Service onboarding popup.
# 5. Initiates device re-enrollment into Jamf MDM.
#
# IMPORTANT: This script must be run as root (sudo).
################################################################################

# -----------------------------
# LOGGING SETUP
# -----------------------------
# Logs will be appended to /var/log/mdm_migration.log and also shown on stdout.
exec > >(tee -a /var/log/mdm_migration.log) 2>&1

# -----------------------------
# HELPER FUNCTIONS
# -----------------------------
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_separator() {
    echo "----------------------------------------------------------------------"
}

# -----------------------------
# PRE-FLIGHT CHECKS
# -----------------------------
print_separator
log_info "Performing pre-flight checks..."

# Check 1: Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Please use sudo."
    exit 1
fi
log_info "Sudo check: PASSED"

# Check 2: Verify curl is installed
if ! command -v curl &> /dev/null; then
    log_error "curl command not found. Please install curl."
    exit 1
fi
log_info "curl check: INSTALLED"

# Check 3: Verify jq is installed (and install if missing)
if ! command -v jq &> /dev/null; then
    log_warn "jq command not found. Attempting to install jq..."
    
    # Check if Homebrew is installed
    if command -v brew &> /dev/null; then
        log_info "Homebrew detected. Installing jq using Homebrew..."
        if brew install jq; then
            log_info "jq successfully installed via Homebrew."
        else
            log_error "Failed to install jq via Homebrew. Falling back to direct download..."
            # Fallback to direct download if Homebrew fails
            JQ_VERSION="1.8.0"
            JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-amd64"
            
            # Try /usr/bin first, fallback to /usr/local/bin if SIP prevents it
            JQ_PATH="/usr/bin/jq"
            if ! curl -L -o "$JQ_PATH" "$JQ_URL" 2>/dev/null || ! chmod +x "$JQ_PATH" 2>/dev/null; then
                log_warn "Cannot write to /usr/bin (likely due to SIP). Using /usr/local/bin instead..."
                JQ_PATH="/usr/local/bin/jq"
                mkdir -p /usr/local/bin
                curl -L -o "$JQ_PATH" "$JQ_URL" && chmod +x "$JQ_PATH"
            fi
            
            if [ -x "$JQ_PATH" ]; then
                log_info "jq successfully installed via direct download to $JQ_PATH"
                hash -r
            else
                log_error "Failed to download and install jq from GitHub."
                exit 1
            fi
        fi
    else
        log_info "Homebrew not found. Installing jq via direct download from GitHub..."
        
        # Download jq binary directly from GitHub releases
        JQ_VERSION="1.8.0"
        JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-amd64"
        
        # Try /usr/bin first, fallback to /usr/local/bin if SIP prevents it
        JQ_PATH="/usr/bin/jq"
        log_info "Downloading jq v${JQ_VERSION} from: $JQ_URL"
        if ! curl -L -o "$JQ_PATH" "$JQ_URL" 2>/dev/null || ! chmod +x "$JQ_PATH" 2>/dev/null; then
            log_warn "Cannot write to /usr/bin (likely due to SIP). Using /usr/local/bin instead..."
            JQ_PATH="/usr/local/bin/jq"
            mkdir -p /usr/local/bin
            curl -L -o "$JQ_PATH" "$JQ_URL" && chmod +x "$JQ_PATH"
        fi
        
        if [ -x "$JQ_PATH" ]; then
            log_info "jq v${JQ_VERSION} successfully installed to $JQ_PATH"
            hash -r
        else
            log_error "Failed to download and install jq from GitHub."
            log_error "Please install jq manually:"
            log_error "  - Using Homebrew: 'brew install jq'"
            log_error "  - Or download from: https://jqlang.github.io/jq/download/"
            exit 1
        fi
    fi
    
    # Verify installation worked
    if ! command -v jq &> /dev/null; then
        log_error "jq installation verification failed."
        exit 1
    fi
else
    log_info "jq is already installed."
fi
log_info "jq check: INSTALLED"

print_separator
log_info "SECTION 1: Removing MDM Profile and Uninstalling ManageEngine Agent"
print_separator

# -----------------------------
# CONFIGURATION
# -----------------------------
log_info "Loading configuration..."
API_TOKEN="<<API_TOKEN>>" # ManageEngine API Token
BASE_URL="<ME_BASE_URL>/api/v1/mdm/devices" # ManageEngine API Base URL
HEADERS=(-H "Authorization: $API_TOKEN" -H "Accept: application/vnd.manageengine.v1+json") # Added Accept header as good practice
PLATFORM_FILTER="ios" # API filter for platform (macOS devices are often categorized as 'ios' in some MDMs)
EXCLUDE_REMOVED="true" # API filter to exclude already removed devices
UNINSTALLER_PATH="/Library/ManageEngine/UEMS_Agent/Uninstaller.app/Contents/MacOS/Uninstaller" # Path to the ME Agent Uninstaller
MAX_WAIT_SECONDS=1800 # Max time (seconds) to wait for MDM profile removal (30 minutes)
POLL_INTERVAL=20 # Interval (seconds) to check for MDM profile removal

# --- Skip Flags ---
# Set these to true to skip the corresponding section
SKIP_MDM_API_REMOVAL=false
SKIP_MDM_AGENT_UNINSTALL=false
SKIP_JAMF_ONBOARDING_PREF=false
SKIP_JAMF_REENROLL=true

# --- Behavior on Failure ---
# If true, certain failures in Section 1 will be logged, and the script will attempt to continue
# to the next enabled section. If false, such failures will cause the script to exit.
ALLOW_SKIP_ON_FAILURE=false

log_info "Configuration loaded."
log_info "SKIP_MDM_API_REMOVAL: $SKIP_MDM_API_REMOVAL"
log_info "SKIP_MDM_AGENT_UNINSTALL: $SKIP_MDM_AGENT_UNINSTALL"
log_info "SKIP_JAMF_ONBOARDING_PREF: $SKIP_JAMF_ONBOARDING_PREF"
log_info "SKIP_JAMF_REENROLL: $SKIP_JAMF_REENROLL"
log_info "ALLOW_SKIP_ON_FAILURE: $ALLOW_SKIP_ON_FAILURE"

# -----------------------------
# STEP 1.1: Get the Serial Number (Common for MDM API Removal)
# -----------------------------
# This step is only relevant if MDM API Removal is not skipped.

serial=""
if [ "$SKIP_MDM_API_REMOVAL" = false ]; then
    log_info "Retrieving device serial number for MDM API removal..."
    serial=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')

    if [ -z "$serial" ]; then
        log_error "Failed to retrieve serial number."
        if [ "$ALLOW_SKIP_ON_FAILURE" = true ]; then
            log_warn "ALLOW_SKIP_ON_FAILURE is true. Cannot proceed with MDM API Removal without serial. Skipping to next major steps."
            SKIP_MDM_API_REMOVAL=true # Force skip API removal as serial is needed
            SKIP_MDM_AGENT_UNINSTALL=true # Also force skip agent uninstall as it depends on profile removal state
        else
            log_error "Exiting because serial number is required and ALLOW_SKIP_ON_FAILURE is false."
            exit 1
        fi
    else
        log_info "Device Serial Number: $serial"
    fi
fi

# Initialize a flag to determine if agent uninstallation should be attempted.
# It should only be attempted if profiles are confirmed removed or API removal was skipped AND profiles aren't found.
should_attempt_agent_uninstall=false

# Initialize API query status flags
api_query_failed=false
device_not_found=false

# -----------------------------
# SECTION 1.A: ManageEngine API Removal & Profile Check
# -----------------------------
if [ "$SKIP_MDM_API_REMOVAL" = false ]; then
    log_info "--- Starting ManageEngine API Removal Process (SECTION 1.A) ---"
    device_id=""
    # STEP 1.2: Query MDM for Device ID
    log_info "Querying ManageEngine MDM for device ID using serial number: $serial..."
    next_url="${BASE_URL}?platform=${PLATFORM_FILTER}&exclude_removed=${EXCLUDE_REMOVED}"
    api_device_found=false

    while [ -n "$next_url" ]; do
        log_info "Fetching devices from: $next_url"
        response=$(curl -s -G "${HEADERS[@]}" "$next_url") # Use -G for query params in URL

        if [ -z "$response" ]; then
            log_error "No response from ManageEngine API at $next_url."
            # This is a more critical API communication failure
            api_query_failed=true  # Set API query failed flag
            if [ "$ALLOW_SKIP_ON_FAILURE" = true ]; then
                log_warn "ALLOW_SKIP_ON_FAILURE is true. API communication failed. Agent uninstall will be skipped."
            else
                log_error "Exiting due to API communication failure and ALLOW_SKIP_ON_FAILURE is false."
                exit 1
            fi
            api_device_found=false # Explicitly mark as not found to skip further API steps
            break # Exit while loop
        fi
        id=$(echo "$response" | jq -r ".devices[] | select(.serial_number==\"$serial\") | .device_id")
        if [ -n "$id" ]; then
            device_id="$id"
            log_info "Found ManageEngine Device ID: $device_id for serial $serial."
            api_device_found=true
            break
        fi
        next_url=$(echo "$response" | jq -r ".paging.next // empty")
        if [ -n "$next_url" ]; then
            log_info "Device not found on this page, checking next page..."
        fi
    done

    if [ "$api_device_found" = true ] && [ -n "$device_id" ]; then
        # STEP 1.3: Remove MDM Profile (Initiate Corporate Wipe)
        log_info "Initiating MDM corporate wipe for ManageEngine Device ID: $device_id..."
        wipe_url="${BASE_URL}/${device_id}/actions/corporate_wipe"
        wipe_response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${HEADERS[@]}" "$wipe_url")

        if [ "$wipe_response_code" == "202" ] || [ "$wipe_response_code" == "200" ]; then
            log_info "Corporate wipe command successfully initiated/processed for device ID $device_id. HTTP Status: $wipe_response_code."

            # STEP 1.4 (Part 1): Wait for MDM profile removal AFTER successful wipe command
            log_info "Waiting for ManageEngine MDM profile removal (max $MAX_WAIT_SECONDS seconds)..."
            elapsed=0
            profile_confirmed_removed_after_api=false
            while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
                profiles_output=$(profiles -P -v | grep "com.manageengine.mdm" || true)
                if [ -z "$profiles_output" ]; then
                    log_info "ManageEngine MDM profile(s) confirmed removed after API wipe."
                    profile_confirmed_removed_after_api=true
                    should_attempt_agent_uninstall=true # Safe to attempt uninstall
                    break
                fi
                sleep $POLL_INTERVAL
                elapsed=$((elapsed + POLL_INTERVAL))
                log_info "ManageEngine MDM profile still present. Waiting... ($elapsed/$MAX_WAIT_SECONDS seconds)"
            done

            if ! $profile_confirmed_removed_after_api; then
                log_error "Timeout: ManageEngine MDM profile still present after $MAX_WAIT_SECONDS seconds post-API wipe."
                if [ "$ALLOW_SKIP_ON_FAILURE" = true ]; then
                    log_warn "ALLOW_SKIP_ON_FAILURE is true. Profile removal timed out, agent uninstall will be skipped."
                    # should_attempt_agent_uninstall remains false
                else
                    log_error "Exiting because profile removal timed out and ALLOW_SKIP_ON_FAILURE is false."
                    exit 1
                fi
            fi
        else
            log_error "Failed to initiate corporate wipe for device ID $device_id. HTTP Status: $wipe_response_code."
            if [ "$ALLOW_SKIP_ON_FAILURE" = true ]; then
                log_warn "ALLOW_SKIP_ON_FAILURE is true. API wipe initiation failed, agent uninstall will be skipped."
                # should_attempt_agent_uninstall remains false
            else
                log_error "Exiting because wipe initiation failed and ALLOW_SKIP_ON_FAILURE is false."
                exit 1
            fi
        fi
    else # Device not found via API or API communication failed earlier
        if [ "$api_query_failed" = false ]; then
            # API worked but device was not found
            log_error "Device with serial number $serial not found in ManageEngine MDM."
            device_not_found=true  # Set device not found flag
        fi
        # If api_query_failed is true, message already logged above
        if [ "$ALLOW_SKIP_ON_FAILURE" = true ]; then
            if [ "$api_query_failed" = true ]; then
                log_warn "ALLOW_SKIP_ON_FAILURE is true. API query failed. Agent uninstall will be skipped."
                # should_attempt_agent_uninstall remains false
            else
                log_warn "ALLOW_SKIP_ON_FAILURE is true. Device not found in API, but proceeding with agent uninstall as device may have local agent installed."
                should_attempt_agent_uninstall=true  # Allow uninstall when device not found
            fi
        else
            log_error "Exiting because device was not found (or API error) and ALLOW_SKIP_ON_FAILURE is false."
            exit 1
        fi
    fi
else
    log_warn "--- ManageEngine API Removal Process (SECTION 1.A) SKIPPED due to configuration. ---"
    log_info "Checking for existing ManageEngine MDM profiles (since API removal was skipped)..."
    profiles_output=$(profiles -P -v | grep "com.manageengine.mdm" || true)
    if [ -z "$profiles_output" ]; then
        log_info "ManageEngine MDM profile(s) are not present (API removal was skipped)."
        should_attempt_agent_uninstall=true # Safe to attempt uninstall if profiles are already gone
    else
        log_warn "ManageEngine MDM profile(s) ARE present (API removal was skipped)."
        log_warn "Agent uninstall will be skipped as profiles are present and API removal was not performed by this script."
        # should_attempt_agent_uninstall remains false
    fi
fi
log_info "--- ManageEngine API Removal / Profile Check (SECTION 1.A) Completed ---"
print_separator

# -----------------------------
# SECTION 1.B: Uninstall ManageEngine Agent
# -----------------------------
if [ "$SKIP_MDM_AGENT_UNINSTALL" = false ]; then
    log_info "--- Starting ManageEngine Agent Uninstall (SECTION 1.B) ---"
    
    # Check API query status and apply appropriate logic
    if [ "$api_query_failed" = true ]; then
        if [ "$ALLOW_SKIP_ON_FAILURE" = false ]; then
            log_error "API query failed and ALLOW_SKIP_ON_FAILURE is false. Script cannot continue safely."
            log_error "Exiting script due to API failure in strict mode."
            exit 1
        else
            log_warn "ManageEngine Agent Uninstall SKIPPED because API query failed."
        fi
    elif [ "$device_not_found" = true ]; then
        log_info "Device not found in API, but proceeding with agent uninstall as device may have local agent installed."
        log_info "Attempting to uninstall ManageEngine Agent..."
        if [ -x "$UNINSTALLER_PATH" ]; then
            if "$UNINSTALLER_PATH" -silent; then
                log_info "ManageEngine agent uninstaller executed successfully."
            else
                log_error "ManageEngine agent uninstaller executed but reported an error (exit code $?). Manual check may be needed."
            fi
        else
            log_warn "ManageEngine Uninstaller not found or not executable at: $UNINSTALLER_PATH."
            log_warn "Agent may need manual uninstallation."
        fi
    elif [ "$should_attempt_agent_uninstall" = true ]; then
        log_info "Proceeding with agent uninstall after successful API operations."
        log_info "Attempting to uninstall ManageEngine Agent..."
        if [ -x "$UNINSTALLER_PATH" ]; then
            if "$UNINSTALLER_PATH" -silent; then
                log_info "ManageEngine agent uninstaller executed successfully."
            else
                log_error "ManageEngine agent uninstaller executed but reported an error (exit code $?). Manual check may be needed."
            fi
        else
            log_warn "ManageEngine Uninstaller not found or not executable at: $UNINSTALLER_PATH."
            log_warn "Agent may need manual uninstallation."
        fi
    else
        log_warn "ManageEngine Agent Uninstall SKIPPED because prerequisite conditions were not met (e.g., profiles still present, or API removal skipped with profiles found)."
    fi
else
    log_warn "--- ManageEngine Agent Uninstall (SECTION 1.B) SKIPPED due to configuration. ---"
fi
log_info "--- ManageEngine Agent Uninstall (SECTION 1.B) Completed ---"
#################### End Removing MDM Profile and Uninstalling ManageEngine Agent ################

print_separator
log_info "SECTION 2: JAMF PREPARATION AND RE-ENROLLMENT"
print_separator

# -----------------------------
# STEP 2.1: Get Logged-in User
# -----------------------------
log_info "Determining currently logged-in GUI user..."
loggedInUser=$(stat -f %Su /dev/console)

if [ -z "$loggedInUser" ] || [ "$loggedInUser" == "root" ] || [ "$loggedInUser" == "loginwindow" ]; then
    log_error "Could not determine a valid logged-in user (Found: '$loggedInUser')."
    log_error "User-specific Jamf steps (Self Service onboarding skip, user-context enrollment) will be skipped or may fail."
    # Decide if script should exit. For now, we'll log and attempt system-level re-enroll.
    # If user context is strictly necessary for all Jamf steps, then `exit 1` here.
    # For `profiles renew`, it can sometimes work without a full user context if run by root.
    # For `defaults write` to user's Library, it will fail without a valid user.
    # Let's make it an error if no valid user for the `defaults` command.
    log_error "Cannot reliably perform user-specific Jamf configurations. Exiting."
    exit 1
fi
loggedInUserID=$(id -u "$loggedInUser")
log_info "Current GUI user: $loggedInUser (UID: $loggedInUserID)"

# -----------------------------
# STEP 2.2: Skipping Onboarding Popup for Jamf Self Service
# -----------------------------
if [ "$SKIP_JAMF_ONBOARDING_PREF" = false ]; then
    log_info "--- Starting Jamf Self Service Onboarding Skip (STEP 2.2) ---"
    log_info "Attempting to set preference to skip Jamf Self Service onboarding popup for user $loggedInUser..."
    # Path to the Self Service preferences file
    plist_path="/Users/$loggedInUser/Library/Preferences/com.jamfsoftware.selfservice.mac.plist"
    key_to_set="com.jamfsoftware.selfservice.onboardingcomplete"

    # Ensure the Preferences directory exists for the user (it should, but good practice)
    user_prefs_dir=$(dirname "$plist_path")
    if [ ! -d "$user_prefs_dir" ]; then
        log_warn "User preferences directory $user_prefs_dir not found. Creating it."
        mkdir -p "$user_prefs_dir"
        chown "$loggedInUser" "$user_prefs_dir"
    fi

    # Run `defaults write` as the logged-in user
    if sudo -u "$loggedInUser" defaults write "$plist_path" "$key_to_set" -bool TRUE; then
        log_info "Successfully set preference to skip Jamf Self Service onboarding for user $loggedInUser."
    else
        log_error "Failed to set preference to skip Jamf Self Service onboarding for user $loggedInUser."
        # This is not critical enough to halt the entire script, so log and continue.
    fi
    log_info "--- Jamf Self Service Onboarding Skip (STEP 2.2) Completed ---"
else
    log_warn "--- Jamf Self Service Onboarding Skip (STEP 2.2) SKIPPED due to configuration. ---"
fi

###################### End Skipping Onboarding Popup ################

# -----------------------------
# STEP 2.3: Re-Enroll Device into Jamf MDM
# -----------------------------
if [ "$SKIP_JAMF_REENROLL" = false ]; then
    log_info "--- Starting Jamf MDM Re-enrollment (STEP 2.3) ---"
    log_info "Initiating re-enrollment into Jamf MDM..."
    log_info "This will attempt to trigger MDM enrollment via Apple Business Manager (ABM/ASM) assignment."

    # Launch the profiles command to renew the MDM enrollment, running as the logged-in user.
    # This is often necessary for the enrollment profile to be correctly processed in the user's context.
    log_info "Attempting to renew MDM enrollment profile as user $loggedInUser (UID: $loggedInUserID)..."
    if launchctl asuser "$loggedInUserID" sudo -u "$loggedInUser" /usr/bin/profiles renew -type enrollment; then
        log_info "Jamf MDM re-enrollment command initiated successfully."
        log_info "Monitor Jamf Pro and the device for enrollment status."
    else
        log_error "Failed to initiate Jamf MDM re-enrollment command using user context."
        log_info "Attempting to run 'profiles renew -type enrollment' as root..."
        if /usr/bin/profiles renew -type enrollment; then
            log_info "Jamf MDM re-enrollment command initiated as root successfully."
            log_info "Monitor Jamf Pro and the device for enrollment status."
        else
            log_error "Failed to initiate Jamf MDM re-enrollment command as root."
            log_error "Manual enrollment or troubleshooting may be required."
            # Consider exiting with an error if this step is critical and fails.
            # For now, log and complete.
        fi
    fi
    log_info "--- Jamf MDM Re-enrollment (STEP 2.3) Completed ---"
else
    log_warn "--- Jamf MDM Re-enrollment (STEP 2.3) SKIPPED due to configuration. ---"
fi

#################### End Re-Enroll Device into Jamf MDM ################

print_separator
log_info "MDM Migration Script Completed."
log_info "Please verify device enrollment status in Jamf Pro and check for any errors in the log: /var/log/mdm_migration.log"
print_separator

exit 0
