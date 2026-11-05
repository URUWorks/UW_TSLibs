/* Loads OpenSSL 3 and Hunspell from a folder, the way Tero Subtitler does, and
   checks them: OpenSSL version, a SHA-256, a real TLS connection (HTTPS GET)
   and a spell check with a small dictionary.
   Usage: libtest <folder> <ssl lib> <crypto lib> <hunspell lib> <tests folder> [host] [OpenSSL major] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#define LOADLIB(p) (void *)LoadLibraryA(p)
#define GETSYM(h, s) (void *)GetProcAddress((HMODULE)(h), s)
static const char *liberr(void) { static char b[64]; sprintf(b, "error %lu", GetLastError()); return b; }
#define SEP "\\"
#else
#include <dlfcn.h>
#define LOADLIB(p) dlopen(p, RTLD_NOW | RTLD_LOCAL)
#define GETSYM(h, s) dlsym(h, s)
static const char *liberr(void) { return dlerror(); }
#define SEP "/"
#endif

static int fails = 0;
#define CHECK(c, msg) do { if (c) printf("ok   %s\n", msg); else { printf("FAIL %s\n", msg); fails++; } } while (0)

static void *load(const char *dir, const char *name) {
    char p[2048];
    snprintf(p, sizeof p, "%s" SEP "%s", dir, name);
    void *h = LOADLIB(p);
    if (!h) { printf("FAIL load %s: %s\n", p, liberr()); fails++; }
    else printf("ok   load %s\n", name);
    return h;
}

static void *sym(void *h, const char *s) {
    void *f = h ? GETSYM(h, s) : NULL;
    if (!f) { printf("FAIL symbol %s\n", s); fails++; }
    return f;
}

int main(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "usage: libtest <folder> <ssl> <crypto> <hunspell> <tests folder> [host]\n"); return 2; }
    const char *dir = argv[1], *host = argc > 6 ? argv[6] : "github.com";
    unsigned long major = argc > 7 ? (unsigned long)atoi(argv[7]) : 3;

    /* crypto first: on Windows libssl finds it next to itself */
    void *crypto = load(dir, argv[3]);
    void *ssl = load(dir, argv[2]);

    const char *(*OpenSSL_version)(int) = sym(crypto, "OpenSSL_version");
    unsigned long (*OpenSSL_version_num)(void) = sym(crypto, "OpenSSL_version_num");
    int (*EVP_Digest)(const void *, size_t, unsigned char *, unsigned int *, const void *, void *) = sym(crypto, "EVP_Digest");
    const void *(*EVP_sha256)(void) = sym(crypto, "EVP_sha256");
    long (*BIO_ctrl)(void *, int, long, void *) = sym(crypto, "BIO_ctrl");
    int (*BIO_write)(void *, const void *, int) = sym(crypto, "BIO_write");
    int (*BIO_read)(void *, void *, int) = sym(crypto, "BIO_read");
    void (*BIO_free_all)(void *) = sym(crypto, "BIO_free_all");
    const void *(*TLS_client_method)(void) = sym(ssl, "TLS_client_method");
    void *(*SSL_CTX_new)(const void *) = sym(ssl, "SSL_CTX_new");
    void (*SSL_CTX_free)(void *) = sym(ssl, "SSL_CTX_free");
    void *(*BIO_new_ssl_connect)(void *) = sym(ssl, "BIO_new_ssl_connect");
    long (*SSL_ctrl)(void *, int, long, void *) = sym(ssl, "SSL_ctrl");
    const char *(*SSL_get_version)(const void *) = sym(ssl, "SSL_get_version");

    if (OpenSSL_version && OpenSSL_version_num) {
        unsigned long v = OpenSSL_version_num();
        printf("     %s\n", OpenSSL_version(0));
        CHECK((v >> 28) == major, "OpenSSL major version");
    }

    if (EVP_Digest && EVP_sha256) {
        unsigned char md[32]; unsigned int n = 0; char hex[65];
        EVP_Digest("abc", 3, md, &n, EVP_sha256(), NULL);
        for (unsigned int i = 0; i < n && i < 32; i++) sprintf(hex + i * 2, "%02x", md[i]);
        hex[64] = 0;
        CHECK(strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0, "SHA-256");
    }

    if (SSL_CTX_new && TLS_client_method && BIO_new_ssl_connect && BIO_ctrl && SSL_ctrl) {
        void *ctx = SSL_CTX_new(TLS_client_method());
        CHECK(ctx != NULL, "SSL_CTX_new");
        if (ctx) {
            char target[300], req[512], buf[256] = {0};
            void *b = BIO_new_ssl_connect(ctx), *s = NULL;
            snprintf(target, sizeof target, "%s:443", host);
            BIO_ctrl(b, 100 /* BIO_C_SET_CONNECT */, 0, target);
            BIO_ctrl(b, 110 /* BIO_C_GET_SSL */, 0, &s);
            if (s) SSL_ctrl(s, 55 /* SSL_CTRL_SET_TLSEXT_HOSTNAME */, 0, (void *)host);
            long r = BIO_ctrl(b, 101 /* BIO_C_DO_STATE_MACHINE */, 0, NULL);
            CHECK(r > 0, "TLS handshake");
            if (r > 0) {
                printf("     %s with %s\n", SSL_get_version(s), host);
                snprintf(req, sizeof req, "HEAD / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", host);
                BIO_write(b, req, (int)strlen(req));
                int n = BIO_read(b, buf, sizeof buf - 1);
                if (n > 0) buf[n] = 0;
                char *eol = strchr(buf, '\r'); if (eol) *eol = 0;
                printf("     %s\n", buf);
                CHECK(strncmp(buf, "HTTP/1.1 ", 9) == 0, "HTTPS response");
            }
            BIO_free_all(b);
            SSL_CTX_free(ctx);
        }
    }

    void *hs = load(dir, argv[4]);
    void *(*Hunspell_create)(const char *, const char *) = sym(hs, "Hunspell_create");
    void (*Hunspell_destroy)(void *) = sym(hs, "Hunspell_destroy");
    int (*Hunspell_spell)(void *, const char *) = sym(hs, "Hunspell_spell");
    int (*Hunspell_suggest)(void *, char ***, const char *) = sym(hs, "Hunspell_suggest");
    void (*Hunspell_free_list)(void *, char ***, int) = sym(hs, "Hunspell_free_list");
    if (Hunspell_create && Hunspell_spell && Hunspell_suggest) {
        char aff[2048], dic[2048];
        snprintf(aff, sizeof aff, "%s" SEP "test.aff", argv[5]);
        snprintf(dic, sizeof dic, "%s" SEP "test.dic", argv[5]);
        void *h = Hunspell_create(aff, dic);
        CHECK(h != NULL, "Hunspell_create");
        if (h) {
            CHECK(Hunspell_spell(h, "hello") != 0, "spell hello");
            CHECK(Hunspell_spell(h, "helo") == 0, "spell helo (wrong)");
            char **list = NULL;
            int n = Hunspell_suggest(h, &list, "helo");
            int found = 0;
            for (int i = 0; i < n; i++) if (strcmp(list[i], "hello") == 0) found = 1;
            CHECK(found, "suggest hello for helo");
            if (n > 0) Hunspell_free_list(h, &list, n);
            Hunspell_destroy(h);
        }
    }

    printf(fails ? "FAILURES: %d\n" : "ALL OK\n", fails);
    return fails != 0;
}
