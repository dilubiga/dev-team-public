#!/usr/bin/env bats
# Tests for scripts/build-prompts.sh

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
    SCRIPT="${REPO_ROOT}/agent-playbook/scripts/build-prompts.sh"
    TMPDIR="$(mktemp -d)"
    BODY_DIR="${TMPDIR}/agents/_body"
    SKILLS_DIR="${TMPDIR}/skills-inlined"
    AGENTS_OUT="${TMPDIR}/agents"
    CHATMODES_OUT="${TMPDIR}/chatmodes"
    mkdir -p "${BODY_DIR}" "${SKILLS_DIR}"
    cp "${REPO_ROOT}/agent-playbook/scripts/tests/fixtures/sample.body.md" \
       "${BODY_DIR}/sample.body.md"
    cp "${REPO_ROOT}/agent-playbook/scripts/tests/fixtures/sample.skill.md" \
       "${SKILLS_DIR}/sample.md"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "build-prompts: emits a Claude wrapper with Claude frontmatter" {
    run bash "${SCRIPT}" \
        --body-dir  "${BODY_DIR}" \
        --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" \
        --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    [ -f "${AGENTS_OUT}/sample.md" ]
    grep -q '^name: sample$' "${AGENTS_OUT}/sample.md"
    grep -q '^tools: ' "${AGENTS_OUT}/sample.md"
}

@test "build-prompts: emits a Copilot chatmode with Copilot frontmatter" {
    run bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    [ -f "${CHATMODES_OUT}/sample.chatmode.md" ]
    grep -q '^description: ' "${CHATMODES_OUT}/sample.chatmode.md"
    grep -q "^tools: \['" "${CHATMODES_OUT}/sample.chatmode.md"
    # Claude-only `name:` field must be absent in the Copilot variant
    ! grep -q '^name: ' "${CHATMODES_OUT}/sample.chatmode.md"
}

@test "build-prompts: inlines skill references in the Copilot variant only" {
    run bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    # Sentinel string lives inside fixtures/sample.skill.md
    grep -q 'INLINED-SKILL-MARKER' "${CHATMODES_OUT}/sample.chatmode.md"
    ! grep -q 'INLINED-SKILL-MARKER' "${AGENTS_OUT}/sample.md"
    # The Claude variant keeps the original skill reference
    grep -q 'SUPERPOWERS_SKILLS_DIR' "${AGENTS_OUT}/sample.md"
}

@test "build-prompts: is idempotent" {
    bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    sha1_a=$(sha1sum "${AGENTS_OUT}/sample.md" "${CHATMODES_OUT}/sample.chatmode.md")
    bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    sha1_b=$(sha1sum "${AGENTS_OUT}/sample.md" "${CHATMODES_OUT}/sample.chatmode.md")
    [ "${sha1_a}" = "${sha1_b}" ]
}
