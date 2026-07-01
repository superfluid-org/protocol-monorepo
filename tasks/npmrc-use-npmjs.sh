cat <<EOF
registry=https://registry.npmjs.org/
EOF

if [ -n "$NPMJS_TOKEN" ]; then
  echo "//registry.npmjs.org/:_authToken=${NPMJS_TOKEN}" >> .npmrc
fi
