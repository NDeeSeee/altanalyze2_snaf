source '/mnt/disks/cromwell_root/gcs_transfer.sh'

timestamped_message 'Localization script execution started...'


# No reference disks mounted since not requested in workflow options.





# Localize files from source bucket 'fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f' to container parent directory '/mnt/disks/cromwell_root'.
files_to_localize_dc67348179a66a8b2e51d24c9b1859f9=(
  "terra-885aa3ed"   # project to use if requester pays
  "3" # max transfer attempts
  "/mnt/disks/cromwell_root/" # container parent directory
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/fdc8247e-580e-474f-9d27-2ba7b3e6971f/SplicingAnalysis/c7fb51df-5a1e-490d-8cef-26e005032cc8/call-BamToBedScatter/shard-2/script"
)

localize_files "${files_to_localize_dc67348179a66a8b2e51d24c9b1859f9[@]}"
       



# Localize files from source bucket 'fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c' to container parent directory '/mnt/disks/cromwell_root/fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files'.
files_to_localize_0f541575c32f695a45afe500e1891704=(
  "terra-885aa3ed"   # project to use if requester pays
  "3" # max transfer attempts
  "/mnt/disks/cromwell_root/fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/" # container parent directory
  "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-1122O-1226-SM-5H113.Aligned.sortedByCoord.out.patched.md.bam.bai"
  "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-1122O-1226-SM-5H113.Aligned.sortedByCoord.out.patched.md.bam"
)

localize_files "${files_to_localize_0f541575c32f695a45afe500e1891704[@]}"
       

timestamped_message 'Localization script execution complete.'