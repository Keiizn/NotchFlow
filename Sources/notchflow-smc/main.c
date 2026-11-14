// notchflow-smc — assistant minimal de gestion de charge pour NotchFlow.
//
// Il n'accepte qu'une liste FERMÉE de commandes (pas d'écriture SMC arbitraire) :
//   notchflow-smc version
//   notchflow-smc status
//   notchflow-smc charging on|off     (root requis)
//   notchflow-smc adapter  on|off     (root requis : off = décharge forcée sur secteur)
//
// Installé dans /usr/local/libexec (propriété root) et autorisé sans mot de passe
// via /etc/sudoers.d/notchflow, uniquement pour ce binaire.
//
// Clés SMC prises en charge :
//   - Apple Silicon, firmware récent (macOS 15+) : CHTE (charge), CHIE (adaptateur)
//   - firmware plus ancien / Intel                : CH0B + CH0C (charge), CH0I (adaptateur)

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HELPER_VERSION "2"

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t g_conn = 0;

static UInt32 key_code(const char *key) {
    return ((UInt32)(unsigned char)key[0] << 24) | ((UInt32)(unsigned char)key[1] << 16) |
           ((UInt32)(unsigned char)key[2] << 8) | (UInt32)(unsigned char)key[3];
}

static kern_return_t smc_call(SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t outputSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, input, sizeof(SMCKeyData_t), output, &outputSize);
}

static int smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    return result == kIOReturnSuccess ? 0 : -1;
}

static int smc_key_size(const char *key, UInt32 *size) {
    SMCKeyData_t input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key_code(key);
    input.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&input, &output) != kIOReturnSuccess || output.result != 0) return -1;
    *size = output.keyInfo.dataSize;
    return 0;
}

static int smc_read(const char *key, unsigned char *buffer, UInt32 *size) {
    UInt32 keySize = 0;
    if (smc_key_size(key, &keySize) != 0 || keySize == 0) return -1;
    SMCKeyData_t input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key_code(key);
    input.keyInfo.dataSize = keySize;
    input.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&input, &output) != kIOReturnSuccess || output.result != 0) return -1;
    if (keySize > 32) keySize = 32;
    memcpy(buffer, output.bytes, keySize);
    *size = keySize;
    return 0;
}

static int smc_write(const char *key, const unsigned char *bytes, UInt32 count) {
    UInt32 keySize = 0;
    if (smc_key_size(key, &keySize) != 0 || keySize == 0) return -1;
    SMCKeyData_t input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key_code(key);
    input.data8 = SMC_CMD_WRITE_BYTES;
    input.keyInfo.dataSize = keySize;
    memcpy(input.bytes, bytes, count < keySize ? count : keySize);
    if (smc_call(&input, &output) != kIOReturnSuccess || output.result != 0) return -1;
    return 0;
}

static int has_key(const char *key) {
    UInt32 size = 0;
    return smc_key_size(key, &size) == 0 && size > 0;
}

static int read_byte(const char *key, int *value) {
    unsigned char buffer[32] = {0};
    UInt32 size = 0;
    if (smc_read(key, buffer, &size) != 0) return -1;
    *value = buffer[0];
    return 0;
}

// --- Commandes ---------------------------------------------------------------

// Écrit puis relit la clé : certaines écritures sont acceptées par le SMC sans effet.
static int write_verified(const char *key, const unsigned char *bytes, UInt32 count) {
    if (smc_write(key, bytes, count) != 0) return -1;
    unsigned char buffer[32] = {0};
    UInt32 size = 0;
    if (smc_read(key, buffer, &size) != 0) return 0;   // lecture impossible : on fait confiance
    return buffer[0] == bytes[0] ? 0 : -1;
}

// On écrit sur TOUTES les clés présentes (firmware récent et ancien) : selon les
// modèles et versions de macOS, une seule des deux familles est réellement active.
static int set_charging(int enabled) {
    int found = 0, ok = 0;
    if (has_key("CHTE")) {
        found = 1;
        unsigned char value[4] = { enabled ? 0x00 : 0x01, 0, 0, 0 };
        if (write_verified("CHTE", value, 4) == 0) ok = 1;
    }
    if (has_key("CH0B")) {
        found = 1;
        unsigned char value[1] = { enabled ? 0x00 : 0x02 };
        int b = write_verified("CH0B", value, 1);
        int c = has_key("CH0C") ? write_verified("CH0C", value, 1) : 0;
        if (b == 0 && c == 0) ok = 1;
    }
    if (!found) return -2;
    return ok ? 0 : -1;
}

static int set_adapter(int enabled) {
    int found = 0, ok = 0;
    if (has_key("CHIE")) {
        found = 1;
        unsigned char value[1] = { enabled ? 0x00 : 0x08 };
        if (write_verified("CHIE", value, 1) == 0) ok = 1;
    }
    if (has_key("CH0I")) {
        found = 1;
        unsigned char value[1] = { enabled ? 0x00 : 0x01 };
        if (write_verified("CH0I", value, 1) == 0) ok = 1;
    }
    if (!found) return -2;
    return ok ? 0 : -1;
}

// État réel : la charge est coupée si l'une des clés actives le dit.
static int charging_disabled(int *known) {
    int value = 0, disabled = 0;
    *known = 0;
    if (has_key("CHTE") && read_byte("CHTE", &value) == 0) { *known = 1; if (value != 0) disabled = 1; }
    if (has_key("CH0B") && read_byte("CH0B", &value) == 0) { *known = 1; if (value != 0) disabled = 1; }
    return disabled;
}

static int adapter_disabled(int *known) {
    int value = 0, disabled = 0;
    *known = 0;
    if (has_key("CHIE") && read_byte("CHIE", &value) == 0) { *known = 1; if (value != 0) disabled = 1; }
    if (has_key("CH0I") && read_byte("CH0I", &value) == 0) { *known = 1; if (value != 0) disabled = 1; }
    return disabled;
}

static void print_status(void) {
    const char *chargingKey = has_key("CHTE") ? (has_key("CH0B") ? "CHTE+CH0B" : "CHTE") : (has_key("CH0B") ? "CH0B" : "none");
    const char *adapterKey = has_key("CHIE") ? (has_key("CH0I") ? "CHIE+CH0I" : "CHIE") : (has_key("CH0I") ? "CH0I" : "none");
    int chargingKnown = 0, adapterKnown = 0;
    int chargingOff = charging_disabled(&chargingKnown);
    int adapterOff = adapter_disabled(&adapterKnown);

    printf("version=%s\n", HELPER_VERSION);
    printf("charging_key=%s\n", chargingKey);
    printf("adapter_key=%s\n", adapterKey);
    printf("charging=%s\n", chargingKnown ? (chargingOff ? "disabled" : "enabled") : "unknown");
    printf("adapter=%s\n", adapterKnown ? (adapterOff ? "disabled" : "enabled") : "unknown");
}

static int usage(void) {
    fprintf(stderr, "usage: notchflow-smc version | status | charging on|off | adapter on|off\n");
    return 64;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return usage();

    if (strcmp(argv[1], "version") == 0) {
        printf("%s\n", HELPER_VERSION);
        return 0;
    }

    if (smc_open() != 0) {
        fprintf(stderr, "error: impossible d'ouvrir le SMC\n");
        return 3;
    }

    int code = 0;
    if (strcmp(argv[1], "status") == 0 && argc == 2) {
        print_status();
    } else if ((strcmp(argv[1], "charging") == 0 || strcmp(argv[1], "adapter") == 0) && argc == 3) {
        int enabled;
        if (strcmp(argv[2], "on") == 0) enabled = 1;
        else if (strcmp(argv[2], "off") == 0) enabled = 0;
        else { IOServiceClose(g_conn); return usage(); }

        if (geteuid() != 0) {
            fprintf(stderr, "error: droits root requis\n");
            code = 2;
        } else {
            int result = strcmp(argv[1], "charging") == 0 ? set_charging(enabled) : set_adapter(enabled);
            if (result == -2) { fprintf(stderr, "error: clé SMC non prise en charge sur ce Mac\n"); code = 4; }
            else if (result != 0) { fprintf(stderr, "error: écriture SMC refusée\n"); code = 5; }
            else printf("ok\n");
        }
    } else {
        code = usage();
    }

    IOServiceClose(g_conn);
    return code;
}
