source '/mnt/disks/cromwell_root/gcs_transfer.sh'

timestamped_message 'Localization script execution started...'


# No reference disks mounted since not requested in workflow options.





# Localize files from source bucket 'fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f' to container parent directory '/mnt/disks/cromwell_root'.
files_to_localize_dc67348179a66a8b2e51d24c9b1859f9=(
  "terra-885aa3ed"   # project to use if requester pays
  "3" # max transfer attempts
  "/mnt/disks/cromwell_root/" # container parent directory
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/script"
)

localize_files "${files_to_localize_dc67348179a66a8b2e51d24c9b1859f9[@]}"
       

timestamped_message 'Localization script execution complete.'