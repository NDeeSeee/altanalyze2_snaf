source '/mnt/disks/cromwell_root/gcs_transfer.sh'

timestamped_message 'Delocalization script execution started...'

# fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f
delocalize_c4f53f83b90b8b669cac43c180f8f9f1=(
  "terra-885aa3ed"       # project
  "3"   # max attempts
  "0" # parallel composite upload threshold, will not be used for directory types
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/memory_retry_rc"
  "/mnt/disks/cromwell_root/memory_retry_rc"
  "optional"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/rc"
  "/mnt/disks/cromwell_root/rc"
  "required"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/stdout"
  "/mnt/disks/cromwell_root/stdout"
  "required"
  "text/plain; charset=UTF-8"
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/stderr"
  "/mnt/disks/cromwell_root/stderr"
  "required"
  "text/plain; charset=UTF-8"
  "directory"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/glob-2d1abde47b9c06d87a549d7187f55ad5/"
  "/mnt/disks/cromwell_root/glob-2d1abde47b9c06d87a549d7187f55ad5"
  "required"
  ""
  "file"
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/glob-2d1abde47b9c06d87a549d7187f55ad5.list"
  "/mnt/disks/cromwell_root/glob-2d1abde47b9c06d87a549d7187f55ad5.list"
  "required"
  ""
)

delocalize "${delocalize_c4f53f83b90b8b669cac43c180f8f9f1[@]}"
      
timestamped_message 'Delocalization script execution complete.'