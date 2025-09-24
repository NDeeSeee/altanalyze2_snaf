#!/usr/bin/env python3
"""
Script to get cache hit information from Terra workflow execution logs.
"""
import subprocess
import json
import sys
import re

def get_access_token():
    """Get Google Cloud access token."""
    try:
        result = subprocess.run(['gcloud', 'auth', 'print-access-token'], 
                              capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error getting access token: {e}", file=sys.stderr)
        return None

def get_workflow_execution_details(submission_id, access_token):
    """Get detailed workflow execution information including cache hits."""
    workspace_project = "AltAnalyze3_SNAF"
    workspace_name = "AltAnalyze3_SNAF"
    
    url = f"https://api.firecloud.org/api/workspaces/{workspace_project}/{workspace_name}/submissions/{submission_id}"
    
    try:
        result = subprocess.run([
            'curl', '-s', '-H', f'Authorization: Bearer {access_token}', url
        ], capture_output=True, text=True, check=True)
        
        data = json.loads(result.stdout)
        
        # Extract workflow information
        workflows = data.get('workflows', [])
        if not workflows:
            return None
        
        workflow = workflows[0]
        
        # Get workflow execution details
        workflow_id = workflow.get('workflowId', '')
        if not workflow_id:
            return None
            
        # Get detailed execution info
        exec_url = f"https://api.firecloud.org/api/workspaces/{workspace_project}/{workspace_name}/submissions/{submission_id}/workflows/{workflow_id}"
        
        exec_result = subprocess.run([
            'curl', '-s', '-H', f'Authorization: Bearer {access_token}', exec_url
        ], capture_output=True, text=True, check=True)
        
        exec_data = json.loads(exec_result.stdout)
        
        return {
            'submission_id': submission_id,
            'workflow_id': workflow_id,
            'status': workflow.get('status', 'UNKNOWN'),
            'cost': workflow.get('cost', 0),
            'execution_details': exec_data
        }
        
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error getting execution details for {submission_id}: {e}", file=sys.stderr)
        return None

def extract_cache_hits(execution_details):
    """Extract cache hit information from workflow execution details."""
    cache_hits = []
    
    # Look for cache hit information in the execution details
    # This might be in different places depending on Terra's API structure
    if 'calls' in execution_details:
        for call_name, call_info in execution_details['calls'].items():
            if isinstance(call_info, list):
                for call in call_info:
                    if 'cacheHit' in call:
                        cache_hits.append({
                            'call': call_name,
                            'cache_hit': call['cacheHit']
                        })
    
    return cache_hits

def main():
    """Main function to get cache hit information."""
    access_token = get_access_token()
    if not access_token:
        print("Failed to get access token", file=sys.stderr)
        sys.exit(1)
    
    # Successful submission IDs
    successful_submissions = [
        '47b08f0d-86a7-4879-8d9e-d36efcf8aaac',  # Fallopian Tube
        '6e7ecab8-6543-4d72-a3dd-28916e038426',  # Bladder
        'ac27dfdc-821e-4cbe-a6f1-efa094018b42',  # Cervix Uteri (latest)
        '1be3d722-d536-49a1-b8a2-d2b073d96ea8',  # Kidney
        '33b87433-60a1-4817-9758-021154214819',  # Vagina
        'a6773fb0-a65b-4a7e-a583-7406e8c2b9c4',  # Bone Marrow
        '4c384d6d-c87f-402d-86b1-a87057e6cc3a'   # Salivary Gland
    ]
    
    print("Cache Hit Analysis")
    print("=" * 50)
    
    for submission_id in successful_submissions:
        print(f"\nChecking submission: {submission_id}")
        
        details = get_workflow_execution_details(submission_id, access_token)
        if not details:
            print("  Failed to get execution details")
            continue
            
        print(f"  Status: {details['status']}")
        print(f"  Cost: ${details['cost']:.2f}")
        
        cache_hits = extract_cache_hits(details['execution_details'])
        if cache_hits:
            print(f"  Cache hits found: {len(cache_hits)}")
            for hit in cache_hits:
                print(f"    {hit['call']}: {hit['cache_hit']}")
        else:
            print("  No cache hits found")
            
        # Print raw execution details for debugging
        print(f"  Raw execution details keys: {list(details['execution_details'].keys())}")

if __name__ == "__main__":
    main()