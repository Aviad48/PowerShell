# Datacenter Remove Snapshot

## Description

This automation script is designed to safely and efficiently remove VM snapshots in a vCenter environment. It ensures that snapshot deletion follows strict conditions to prevent storage issues.

**Conditions for Deletion:**
1. Snapshots older than **1 day** will be removed (this value can be modified in the script).
2. After removing a snapshot, the **remaining free storage** on the corresponding volume must be **at least 10TB**.

## Features

- ✅ Full logging of all activities
- 📊 Validates storage status using a custom PowerShell function that queries the **Elastic API**
- ⚙️ Executable as part of a **Jenkins pipeline**
- 📧 Sends a full **email report** after execution

## Requirements

- PowerShell 5.1 or higher
- PowerCLI installed and configured
- Access to vCenter with appropriate permissions
- Elastic API endpoint and API key
- Jenkins agent with PowerShell support

## Installation

Clone the repository:

```bash
git clone https://your-gitlab-or-github-url/aviadd/snapshot-remove.git
cd snapshot-remove

