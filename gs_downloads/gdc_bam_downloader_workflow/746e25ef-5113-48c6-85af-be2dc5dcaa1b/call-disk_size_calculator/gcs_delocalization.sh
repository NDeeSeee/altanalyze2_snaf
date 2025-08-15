source '/mnt/disks/cromwell_root/gcs_transfer.sh'

timestamped_message 'Delocalization script execution started...'

# fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f
delocalize_c4f53f83b90b8b669cac43c180f8f9f1=(
  "terra-885aa3ed"       # project
  "3"   # max attempts
  "0" # parallel composite upload threshold, will not be used for directory types
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/memory_retry_rc"
  "/mnt/disks/cromwell_root/memory_retry_rc"
  "optional"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/rc"
  "/mnt/disks/cromwell_root/rc"
  "required"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/stdout"
  "/mnt/disks/cromwell_root/stdout"
  "required"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/stderr"
  "/mnt/disks/cromwell_root/stderr"
  "required"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/94514776-88dd-465a-ab6d-700517838682/gdc_bam_downloader_workflow/746e25ef-5113-48c6-85af-be2dc5dcaa1b/call-disk_size_calculator/file_size.txt"
  "/mnt/disks/cromwell_root/file_size.txt"
  "required"
  ""
)

delocalize "${delocalize_c4f53f83b90b8b669cac43c180f8f9f1[@]}"
      
timestamped_message 'Delocalization script execution complete.'