# MDM Migrate ManageEngine to Jamf 🚀
Also used for Jamf Migration Tool Helper


## 📜 Description
This script is designed to automate the migration of macOS devices from ManageEngine MDM to Jamf MDM. 
It handles the removal of the ManageEngine agent and profiles, and prepares the device for Jamf enrollment. 
It can also serve as a helper utility when using the Jamf Migration Tool, specifically for the ManageEngine deprovisioning steps.

## 📜 Script Key Actions:

The script performs the following key actions:

1.  **Removes the device from ManageEngine MDM**: Utilizes the ManageEngine API to initiate a corporate wipe command, which should remove MDM profiles.
2.  **Validates Profile Removal**: Waits and checks if the ManageEngine MDM profiles have been successfully removed from the device.
3.  **Uninstalls ManageEngine Agent**: If profiles are confirmed removed (or if API removal is skipped and profiles are not present), it attempts to run the ManageEngine agent uninstaller.
4.  **Prepares for Jamf**:
    *   Sets a preference to skip the Jamf Self Service onboarding popup for the current user (if not disabled by `SKIP_JAMF_ONBOARDING_PREF`), need to be set before Enrollment.
5.  **Initiates Jamf Re-enrollment**: Triggers the `profiles renew -type enrollment` command to prompt the device to re-enroll into Jamf MDM (assuming the device is assigned to Jamf Pro via Apple Business Manager or Apple School Manager).

This script is intended for devices managed in Apple Business Manager (ABM) or Apple School Manager (ASM).

Additionally, this script can be used in conjunction with the Jamf Migration Tool. If you are using the Jamf Migration Tool, it's important to set the `SKIP_ABM_REENROLL` parameter in this script to `true`. This is because the Jamf Migration Tool typically handles the re-enrollment process itself, and skipping this step in the script will prevent conflicts or redundant actions.

## ⚙️ How to Use

### 1. Place the Script on the Target Mac (Manual Method)

*   Copy the `Migrate-ManageEngine2Jamf.sh` script to a location on the target Mac, for example:
    *   `/usr/local/bin/Migrate-ManageEngine2Jamf.sh`
    *   `/Library/Scripts/Migrate-ManageEngine2Jamf.sh`

### 2. Make the Script Executable (Manual Method)

*   Open Terminal on the target Mac and run:
    ```bash
    sudo chmod +x /path/to/Migrate-ManageEngine2Jamf.sh
    ```
    For example:
    ```bash
    sudo chmod +x /usr/local/bin/Migrate-ManageEngine2Jamf.sh
    ```
*   To run the script manually:
    ```bash
    sudo /path/to/Migrate-ManageEngine2Jamf.sh
    ```
    **Important**: Test on a non-production Mac first!

### 3. Run Remotely

   **a. Using SSH (if script is already on the Mac):**
   *   Ensure SSH is enabled on the target Mac (System Settings > General > Sharing > Remote Login).
   *   From another machine:
     ```bash
     ssh your_username@target_mac_ip_or_hostname 'sudo /path/to/Migrate-ManageEngine2Jamf.sh'
     ```
     Example:
     ```bash
     ssh adminuser@192.168.1.10 'sudo /usr/local/bin/Migrate-ManageEngine2Jamf.sh'
     ```

   **b. Using curl to download and execute (Script must be hosted online):**
   *   Host the `Migrate-ManageEngine2Jamf.sh` script on a web server or a service like GitHub Gist (use the "Raw" file URL).
   *   From the target Mac's terminal, or via SSH:
     ```bash
     curl -sSL https://your-script-host.com/path/to/Migrate-ManageEngine2Jamf.sh | sudo bash
     ```
     Example (placeholder URL):
     ```bash
     curl -sSL https://gist.githubusercontent.com/youruser/yourgistid/raw/Migrate-ManageEngine2Jamf.sh | sudo bash
     ```
   *   ⚠️ **SECURITY WARNING**: Always review scripts from the internet before executing them with `sudo bash`.

### 4. Using with Jamf Migration Tool

To use this script as part of a Jamf Migration Tool workflow for deprovisioning ManageEngine:

1.  **Configure the Script**:
    *   Open the `Migrate-ManageEngine2Jamf.sh` script.
    *   Set the `SKIP_ABM_REENROLL` parameter to `true`. This is crucial because the Jamf Migration Tool will handle the re-enrollment.
    ```bash
    SKIP_ABM_REENROLL=true
    ```
    *   Ensure all other parameters (like `API_TOKEN`, `BASE_URL`) are correctly configured for your ManageEngine environment.
2.  **Upload Script to Jamf Pro**:
    *   Upload the modified `Migrate-ManageEngine2Jamf.sh` script to your Jamf Pro server (typically found under Settings > Computer Management > Scripts).
3.  **Create a Jamf Pro Policy**:
    *   In Jamf Pro, create a new policy.
    *   Add the uploaded script to this policy.
    *   Set the policy's execution frequency as appropriate (e.g., "Ongoing" if triggered by Jamf Migration Tool, or "Once per computer").
    *   Under the "Custom Event" payload (or similar, depending on your Jamf Pro version), define a custom trigger name for this policy (e.g., `remove_manageengine_mdm`).
    *   Scope this policy to the computers you intend to migrate.
4.  **Configure Jamf Migration Tool**:
    *   In the Jamf Migration Tool's configuration settings, locate the option for specifying a script to run *before* the re-enrollment phase (this might be labeled as "Pre-enrollment script trigger", "Run script before re-enrollment", or similar).
    *   Enter the custom trigger name you defined in the Jamf Pro policy (e.g., `remove_manageengine_mdm`) into this field.

This configuration ensures that the `Migrate-ManageEngine2Jamf.sh` script executes to handle the deprovisioning from ManageEngine before the Jamf Migration Tool proceeds with the Jamf Pro re-enrollment process.

## 🛠️ Configuration & Parameters

The script requires several parameters to be configured directly within the script file before execution.

### Essential Parameters:

These **must** be updated in the script:

*   `API_TOKEN`: Your ManageEngine API Token.
    ```bash
    API_TOKEN="your_manage_engine_api_token_here"
    ```
*   `BASE_URL`: The base URL for your ManageEngine API endpoint.
    ```bash
    BASE_URL="https://your-me-server.com:8383/api/v1/mdm/devices"
    ```
*   `UNINSTALLER_PATH`: Path to the ManageEngine Agent Uninstaller. The default is usually correct, but verify.
    ```bash
    UNINSTALLER_PATH="/Library/ManageEngine/UEMS_Agent/Uninstaller.app/Contents/MacOS/Uninstaller"
    ```

### Other Parameters (Defaults usually okay):

*   `PLATFORM_FILTER`: API filter for platform (default: `"ios"` which often includes macOS).
*   `EXCLUDE_REMOVED`: API filter to exclude already removed devices (default: `"true"`).
*   `MAX_WAIT_SECONDS`: Max time (seconds) to wait for MDM profile removal (default: `1800` / 30 minutes).
*   `POLL_INTERVAL`: Interval (seconds) to check for MDM profile removal (default: `20`).

### Behavior Control Flags:

These flags can be set to `true` or `false` within the script to alter its behavior:

*   `SKIP_MDM_API_REMOVAL`: Set to `true` to skip the ManageEngine API removal step.
    ```bash
    SKIP_MDM_API_REMOVAL=false # Default
    ```
*   `SKIP_MDM_AGENT_UNINSTALL`: Set to `true` to skip the ManageEngine agent uninstallation step.
    ```bash
    SKIP_MDM_AGENT_UNINSTALL=false # Default
    ```
*   `SKIP_JAMF_ONBOARDING_PREF`: Set to `true` to skip setting the Jamf Self Service onboarding preference.
    ```bash
    SKIP_JAMF_ONBOARDING_PREF=false # Default
    ```
*   `SKIP_ABM_REENROLL`: Set to `true` to skip the Jamf MDM re-enrollment step.
    ```bash
    SKIP_ABM_REENROLL=false # Default
    ```

### Behavior on Failure:

*   `ALLOW_SKIP_ON_FAILURE`: If `true`, certain failures (e.g., API communication issues, profile removal timeout) will be logged as warnings, and the script will attempt to continue to the next enabled section. If `false` (default and recommended for production), such failures will cause the script to exit.
    ```bash
    ALLOW_SKIP_ON_FAILURE=false # Default - Recommended for production
    ```
    Use `true` primarily for testing and debugging, understanding the risks.

## 📝 Logging

*   The script logs its output to `/var/log/mdm_migration.log` on the target Mac.
*   Output is also printed to `stdout` (visible in your SSH session or terminal).

Example log entries:
```
[INFO] 2025-06-11 10:00:00 - Performing pre-flight checks...
[ERROR] 2025-06-11 10:00:05 - This script must be run as root. Please use sudo.
[WARN] 2025-06-11 10:05:00 - ALLOW_SKIP_ON_FAILURE is true. Profile removal timed out, agent uninstall will be skipped.
```

## ✅ Pre-flight Checks

Before running the main logic, the script performs several checks:

1.  **Root Privileges**: Ensures the script is run as `root` (using `sudo`).
2.  **`curl` Installation**: Verifies that `curl` is installed.
3.  **`jq` Installation**: Verifies that `jq` (a command-line JSON processor) is installed.

If any of these checks fail, the script will exit.

## 🚦 Script Flow & Sections

The script is divided into logical sections:

### Section 1: Removing MDM Profile and Uninstalling ManageEngine Agent

*   **1.1: ManageEngine API Removal & Profile Check**
    *   Retrieves the device serial number.
    *   Queries the ManageEngine MDM API to find the device ID using the serial number.
    *   If found, initiates a "corporate wipe" command via the API to remove MDM profiles.
    *   Waits for a configurable duration (`MAX_WAIT_SECONDS`), polling to confirm the "com.manageengine.mdm" profiles are removed.
    *   Handles API errors, device not found scenarios, and profile removal timeouts based on the `ALLOW_SKIP_ON_FAILURE` flag.
    *   If `SKIP_MDM_API_REMOVAL` is `true`, this subsection is skipped, but it will check if profiles are already absent.
*   **1.2: Uninstall ManageEngine Agent**
    *   This step only proceeds if:
        *   MDM profiles were successfully removed via API, OR
        *   API removal was skipped (`SKIP_MDM_API_REMOVAL=true`) AND profiles are not currently present.
    *   Attempts to run the ManageEngine agent uninstaller specified by `UNINSTALLER_PATH` in silent mode.
    *   Logs success, failure, or if the uninstaller is not found/executable.
    *   Skipped if `SKIP_MDM_AGENT_UNINSTALL` is `true`.

### Section 2: Jamf Preparation

*   **2.1: Get Logged-in User**
    *   Determines the currently logged-in GUI user. This is crucial for user-specific commands.
    *   If a valid GUI user cannot be determined, the script will exit as user-specific Jamf configurations cannot be reliably performed.
*   **2.2: Skipping Onboarding Popup for Jamf Self Service (User based)**
    *   Attempts to write a preference to the logged-in user's `com.jamfsoftware.selfservice.mac.plist` file to prevent the Jamf Self Service onboarding screen from appearing.
    *   This runs as the logged-in user.
    *   Skipped if `SKIP_JAMF_ONBOARDING_PREF` is `true`.

### Section 3: Re-Enroll via ABM

*   **3: Re-Enroll Device into Jamf MDM** (Labeled as STEP 3 in script comments)
    *   Initiates the MDM re-enrollment process by running `/usr/bin/profiles renew -type enrollment`.
    *   This command prompts the Mac to check its ABM/ASM assignment and pull down the Jamf enrollment profile.
    *   Attempts to run this command first in the context of the logged-in user, then as root if the user-context command fails.
    *   Skipped if `SKIP_ABM_REENROLL` is `true`.
      
## ❗ Important Considerations

*   **Run as Root**: This script **must** be run with `sudo` due to the nature of the operations it performs (MDM profile interaction, agent uninstallation, system-level commands).
*   **Apple Business Manager / Apple School Manager**: For successful re-enrollment into Jamf, the target Mac **must** be assigned to your Jamf Pro server in Apple Business Manager (ABM) or Apple School Manager (ASM).
*   **Testing**: Thoroughly test this script on a non-production Mac before deploying it to multiple devices.
*   **API Credentials**: Secure your ManageEngine `API_TOKEN`. If hosting the script, consider methods to inject credentials securely rather than hardcoding them if the script is publicly accessible. For internal use, hardcoding might be acceptable with controlled access to the script file.
*   **Error Handling**: Review the script's error handling and the `ALLOW_SKIP_ON_FAILURE` flag. For production, it's generally safer to have `ALLOW_SKIP_ON_FAILURE=false` so that issues are surfaced immediately.

---
  
Hope its will help,
Good luck with your migration! 🍀

---

## 📜 Disclaimer

This script is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details and provided "as-is" without any warranties, express or implied. The author(s) and contributor(s) are not responsible for any data loss, system instability, or any other issues that may arise from its use.

**Use this script at your own risk.**

It is strongly recommended to:
*   Thoroughly test this script in a non-production environment before deploying it to any live systems.
*   Understand what each part of the script does before running it.
*   Ensure you have backups of any critical data before proceeding.

By using this script, you acknowledge that you understand the potential risks involved and take full responsibility for any consequences.

---

<div align="center">

**⭐ If this script helps you, please consider giving it a star! ⭐**

[![GitHub stars](https://img.shields.io/github/stars/alcavix/Migrate-me2jamf.svg?style=social&label=Star)](https://github.com/alcavix/Migrate-me2jamf)
[![GitHub forks](https://img.shields.io/github/forks/alcavix/Migrate-me2jamf.svg?style=social&label=Fork)](https://github.com/alcavix/Migrate-me2jamf/fork)

</div>

---

This script was created by **Tomer Alcavi**.

If you find it useful or inspiring, you're welcome to explore and learn from it —  
but please avoid re-publishing or presenting this work (in full or in part) under a different name or without proper credit.
Keeping attribution clear helps support open, respectful collaboration. Thank you!

If you have ideas for improvements or enhancements, I’d love to hear them!  
Open collaboration and respectful feedback are always welcome.

_Made with ❤️ by Tomer Alcavi_

