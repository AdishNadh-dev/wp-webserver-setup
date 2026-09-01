#!/bin/bash

while true; do
    read -p "Do you want to setup? (y/n): " response

    case "$response" in
        y|Y)
            echo "Starting setup..."
            ./setup.sh
            break
            ;;
        n|N)
            echo "Setup skipped."
            break
            ;;
        *)
            echo "Please enter y or n."
            ;;
    esac
done
