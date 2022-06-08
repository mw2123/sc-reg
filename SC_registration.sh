#!/bin/bash
#
#
# Created by Max Wang on 9/27/2020
# Modified version of code from Kenneth Weber and Mark Hoggarth
#
# This script conducts nonlinear registration of a spinal cord fMRI dataset to
# the PAM50 template. Note that the data must be organized in BIDS format
# The BIDS specification can be found at:
# https://bids-specification.readthedocs.io/en/stable/
#
# Inputs:
# 1) BIDS Folder
# 2) Subject ID
# 3) Session number
# 4) Anatomical image file
# 5) Functional image file
# 6) Mask Directory
# 7) Functional mask file
# Outputs (to derivatives folder):
# 1) PAM50 to func warping field (warp_PAM50_t2s2func_mean.nii.gz)
# 2) Func to PAM50 warping field (warp_func2PAM50_t2s.nii.gz)
# 3) PAM50 template warped to func space (PAM50_t2s_reg.nii.gz)
# 4) PAM50 labels warped to func space (/label/template)

function usage()
{
cat << EOF
DESCRIPTION
  Register anatomical and functional spinal cord images. Note that the file structure must be:
  Top directory with this code -> BIDS -> sourcedata & derivatives -> subject -> session -> anat & func
USAGE
  `basename ${0}` -f <folder> -s <subject> -x <session> -a <anatomical> -b <functional> -m <mask directory> -k <mask file>
  # Example: bash SC_registration.sh -f ./BIDS -s sub-02 -x Pilot -a sub-02_acq-SC_T2w.nii.gz -b sub-02_task-01_acq-SC_bold.nii.gz -m ~/Documents/box-finished/kim -k 2a_KJH.nii.gz
MANDATORY ARGUMENTS
  -f <folder>				BIDS folder
  -s <subject>				Subject Study ID (e.g., sub-HC##)
  -x <session>				Session (e.g., baselinespinalcord)
  -a <anatomical>           Anatomical Image
  -b <functional>           Fucntional Image
  -m <mask directory>       Mask Directory
  -k <mask>                 Functional Mask
EOF
}

if [ ! ${#@} -gt 0 ]; then
    usage `basename ${0}`
    exit 1
fi

#Initialization of variables

scriptname=${0}
folder=
subject=
session=
T2w=
func=
maskdir=
mask=

while getopts “hf:s:x:a:b:T:F:m:k:” OPTION
do
	case $OPTION in
	 h)
			usage
			exit 1
			;;
	 f)
		folder=$OPTARG
            ;;
	 s)
		subject=$OPTARG
            ;;
	 x)
		session=$OPTARG
			;;
     a)
		anat=$OPTARG
			;;
     b)
		func=$OPTARG
			;;
	 T)
		T2w=$OPTARG
			;;
	 F)
		func=$OPTARG
			;;
         m)
                maskdir=$OPTARG
                        ;;
         k)
                mask=$OPTARG
                    ;;
	 ?)
		 usage
		 exit
		 ;;
     esac
done

# # Check the parameters
if [[ -z ${folder} ]]; then
	 echo "ERROR: Folder not specified. Exit program."
     exit 1
fi
if [[ -z ${subject} ]]; then
     echo "ERROR: Subject not specified. Exit program."
     exit 1
fi
if [[ -z ${session} ]]; then
    echo "ERROR: Session not specified. Exit program."
    exit 1
fi
if [[ -z ${anat} ]]; then
	 echo "ERROR: Anatomical Image not specified. Exit program."
     exit 1
fi
if [[ -z ${func} ]]; then
	 echo "ERROR: Functional Image not specified. Exit program."
     exit 1
fi
if [[ -z ${maskdir} ]]; then
	 echo "ERROR: Functional Mask Directory not specified. Exit program."
     exit 1
fi
if [[ -z ${mask} ]]; then
	 echo "ERROR: Functional Mask not specified. Exit program."
     exit 1
fi

# Setup source path and derivatives directory structure
cd ${folder}
data_path=`pwd` # Set data path to current directory
mkdir ${data_path}/derivatives/${subject}
mkdir ${data_path}/derivatives/${subject}/ses-${session}
mkdir ${data_path}/derivatives/${subject}/ses-${session}/anat
mkdir ${data_path}/derivatives/${subject}/ses-${session}/func

cp -rf ${data_path}/sourcedata/${subject}/ses-${session} ${data_path}/derivatives/${subject}/

# Begin Anatomical Registration

    # Change to derivatives folder
	cd ${data_path}/derivatives/${subject}/ses-${session}/anat

    # Copy T2w image to derivatives folder
	cp ${data_path}/sourcedata/${subject}/ses-${session}/anat/${anat} ./

    # Rename anatomical image for simplicity
    mv ${anat} anat.nii.gz

    echo Determine which z slices to crop include
    # Display anatomical image
    fsleyes anat &

    echo -n Enter the inferior slice number and press ENTER:
		read inferior

    echo -n Enter the superior slice number and press ENTER:
		read superior

	number_of_slices=$(echo "${superior} - ${inferior}" | bc)

    fslroi anat anat_cropped 0 -1 0 -1 ${inferior} ${number_of_slices}

    # Segment SC using deep learning SCT tool
	sct_deepseg_sc -i anat_cropped.nii.gz -c t2 -centerline svm -kernel 2d

    echo -n Touch up anatomical mask
    fsleyes anat_cropped.nii.gz -cm greyscale anat_cropped_seg.nii.gz -cm red -a 70.0

    # Label 3rd and 7th Cervical Vertebrae
    sct_label_utils -i anat_cropped.nii.gz -o anat_cropped_labels.nii.gz -create-viewer 3,7

    # Register template and anatomical images
    sct_register_to_template -i anat_cropped.nii.gz -s anat_cropped_seg.nii.gz -l anat_cropped_labels.nii.gz -c t2

    # Check regsitration
    fsleyes anat_cropped.nii.gz template2anat.nii.gz

    fsleyes ${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz anat2template.nii.gz

# Begin Processing Functional Data

    # Change directory to functional data path
	cd ${data_path}/derivatives/${subject}/ses-${session}/func

    # Copy functional data to derivatives folder
    cp ${data_path}/sourcedata/${subject}/ses-${session}/func/${func} ./
    cp ${maskdir}/${mask} ./

    # Rename functional data
    mv ${func} func.nii.gz
    mv ${mask} funcmask.nii.gz

    # Create mean image over time series
    fslmaths func.nii.gz -Tmean func_mean.nii.gz

	#Run registration and warp template and display
	sct_register_multimodal -i ${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz -iseg ${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz -d func_mean.nii.gz -dseg funcmask.nii.gz  -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../anat/warp_template2anat.nii.gz -initwarpinv ../anat/warp_anat2template.nii.gz

    # Show results of registration
    fsleyes func_mean.nii.gz PAM50_t2s_reg.nii.gz -cm red -a 25.0

    # Warp template to functional data and display
	sct_warp_template -d func_mean.nii.gz -w warp_PAM50_t2s2func_mean.nii.gz

    # Show final result from wapred atlas to functional space
    fsleyes func_mean.nii.gz -cm greyscale -a 100.0 label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 50.0 label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 50.0 &


exit 0
