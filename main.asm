;===============================================================================
; MSP430G2553 - Simon Says Memory Game (Fixed & Optimized)
;
; Proje Gereksinimleri & Durum:
;  - Idle Animasyonu (Bekleme modu): EKLENDİ
;  - Başlangıç Mekanizması: Uzun basış (~1 sn) ile zorluk seçerek başlama. EKLENDİ
;  - Seviyeler: 3 Seviye (Uzunluklar 2, 3, 5). EKLENDİ
;  - Doğru Giriş: Dahili YEŞİL LED yanar + 2 sn bekleme. EKLENDİ
;  - Yanlış Giriş: Dahili KIRMIZI LED yanar + Tüm LED'ler yanıp söner. EKLENDİ
;  - Kazanma: Harici WIN LED (P2.4) sürekli yanar. EKLENDİ
;  - BONUS: Rastgele Desen Üretimi (Xorshift16). EKLENDİ
;  - BONUS: Easter Egg (Tüm tuşlara aynı anda basış). EKLENDİ
;  - BONUS: Zorluk Seviyeleri (Hız değişimi). EKLENDİ
;
; Pin Bağlantıları:
;   Oyun LED'leri : P2.0, P2.1, P2.2, P2.3
;   WIN LED       : P2.4 (Harici Yeşil)
;   KIRMIZI LED   : P1.0 (Kart Üzerinde)
;   YEŞİL LED     : P1.6 (Kart Üzerinde)
;   Butonlar      : P1.1, P1.2, P1.3, P1.4 (Pull-up dirençli, basınca 0 olur)
;===============================================================================

            .cdecls C,LIST,"msp430.h"
            .def    RESET

;----------------------------
; Sabitler / Tanımlamalar
;----------------------------
GAME_LEDS       .equ    (BIT0|BIT1|BIT2|BIT3)   ; P2.0..P2.3
WIN_LED         .equ    BIT4                    ; P2.4

RED_LED         .equ    BIT0                    ; P1.0
GRN_LED         .equ    BIT6                    ; P1.6

BTN_MASK        .equ    (BIT1|BIT2|BIT3|BIT4)   ; P1.1..P1.4

; Durumlar (State Machine)
S_IDLE          .equ    0
S_PLAYER        .equ    1
S_LEVEL_WIN     .equ    2
S_LEVEL_LOSE    .equ    3

NUM_LEVELS      .equ    3
MAX_STEPS       .equ    16                      ; Maksimum 16 adımlık hafıza

; Zamanlama Eşikleri (DELAY_MS döngüsüne ve çağrılma sıklığına bağlı)
; IDLE döngüsü yaklaşık 20ms sürer. 1 saniye için ~50 saykıl gerekir.
START_HOLD_T    .equ    50                      ; ~1 sn basılı tutma
EGG_HOLD_T      .equ    50                      ; ~1 sn basılı tutma

;-------------------------------------------------------------------------------
            .text
            .retain
            .retainrefs

;===============================================================================
; RESET / BAŞLANGIÇ AYARLARI
;===============================================================================
RESET:
            mov.w   #__STACK_END, SP        ; FIX: Stack pointer'ı RAM'in en sonuna ayarla

            mov.w   #WDTPW|WDTHOLD, &WDTCTL ; Watchdog Timer'ı durdur

            ; DCO Kalibrasyonu (1 MHz) - Zamanlamaların doğru olması için şart
            mov.b   &CALBC1_1MHZ, &BCSCTL1
            mov.b   &CALDCO_1MHZ, &DCOCTL

            ; WDT'yi Interval modunda başlat (Rastgele sayı üretimi için 'seed' karıştırma)
            mov.w   #WDTPW|WDTTMSEL|WDTCNTCL|WDTIS1|WDTIS0, &WDTCTL
            bis.b   #WDTIE, &IE1

;----------------------------
; Port Ayarları
;----------------------------
; P2: Oyun LED'leri ve WIN LED çıkış olarak ayarlanır
            bis.b   #(GAME_LEDS|WIN_LED), &P2DIR
            bic.b   #GAME_LEDS, &P2OUT      ; Oyun LED'lerini söndür (WIN LED'e dokunma)

; P1: Dahili LED'ler çıkış
            bis.b   #(RED_LED|GRN_LED), &P1DIR
            bic.b   #(RED_LED|GRN_LED), &P1OUT

; P1: Butonlar giriş ve Pull-Up dirençleri aktif
            bic.b   #BTN_MASK, &P1DIR       ; Giriş yap
            bis.b   #BTN_MASK, &P1REN       ; Dirençleri aktif et
            bis.b   #BTN_MASK, &P1OUT       ; Pull-up seç (Basılınca 0, Bırakınca 1)

; Buton Kesmeleri (Düşen kenar - Falling Edge)
            bis.b   #BTN_MASK, &P1IES       ; 1 -> 0 geçişinde tetikle
            bic.b   #BTN_MASK, &P1IFG       ; Bayrakları temizle
            bis.b   #BTN_MASK, &P1IE        ; Kesmeleri aç

; Değişkenleri Sıfırla
            mov.w   #S_IDLE, &STATE
            mov.w   #0, &LEVEL
            mov.w   #0, &PROG
            mov.w   #0, &BTN_EVENT
            mov.w   #0, &START_CNT
            mov.w   #0, &EGG_CNT
            mov.w   #0, &DIFF

            bis.w   #GIE, SR                ; Global kesmeleri aç

;===============================================================================
; ANA DÖNGÜ (Main Loop)
;===============================================================================
MAIN:
;----------------------------
; IDLE: Bekleme Animasyonu + Başlatma Kontrolü
;----------------------------
IDLE_STATE:
            mov.w   #S_IDLE, &STATE
            bic.b   #(RED_LED|GRN_LED), &P1OUT  ; Dahili LED'leri kapat
            bic.b   #GAME_LEDS, &P2OUT          ; Oyun LED'lerini kapat (WIN LED kalsın)

            mov.w   #0, &START_CNT
            mov.w   #0, &EGG_CNT

IDLE_LOOP:
            ; Animasyon: LED0 -> LED1 -> LED2 -> LED3 sırasıyla yak
            mov.w   #0, r10                     ; r10 = led indeksi (0..3)

.IDLE_NEXT_LED:
            call    #IDLE_CHECK_INPUTS          ; Tuş kontrolü (Start veya Easter Egg için)

            ; Seçili LED'i yak
            mov.w   r10, r11
            call    #IDX_TO_LED_MASK            ; r12 içinde maske döner
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            mov.w   #10, r14                    ; 10ms bekle
            call    #DELAY_MS

            ; Söndür
            bic.b   #GAME_LEDS, &P2OUT
            mov.w   #10, r14                    ; 10ms bekle
            call    #DELAY_MS

            ; Bir sonraki LED'e geç
            inc.w   r10
            cmp.w   #4, r10
            jne     .IDLE_NEXT_LED

            jmp     IDLE_LOOP

;----------------------------
; START GAME: Oyun Başlatma
;----------------------------
START_GAME:
            bic.b   #WIN_LED, &P2OUT            ; Yeni oyun başlıyor, WIN LED'i söndür

            ; Oyun sırasında WDT'yi durdur (Kararlılık için)
            mov.w   #WDTPW|WDTHOLD, &WDTCTL
            bic.b   #WDTIE, &IE1

            mov.w   #0, &LEVEL
            mov.w   #0, &PROG
            mov.w   #0, &BTN_EVENT

            call    #GEN_RANDOM_PATTERN         ; Rastgele desen üret (ORDER dizisini doldur)

            jmp     SHOW_LEVEL

;----------------------------
; SHOW LEVEL: Deseni Göster
;----------------------------
SHOW_LEVEL:
            mov.w   #0, &PROG
            call    #SHOW_PATTERN               ; LED dizisini yak/söndür

            ; Oyuncu girişine izin ver
            mov.w   #S_PLAYER, &STATE
            mov.w   #0, &BTN_EVENT
            bic.b   #BTN_MASK, &P1IFG
            bis.b   #BTN_MASK, &P1IE

; Oyuncunun tuşlara basmasını bekle
PLAYER_LOOP:
            cmp.w   #S_PLAYER, &STATE
            jne     PLAYER_DONE                 ; Eğer süre bittiyse veya hata yaptıysa çık

            mov.w   &BTN_EVENT, r12
            cmp.w   #0, r12
            jeq     PLAYER_LOOP                 ; Henüz tuşa basılmadı

            ; Olayı işle: r12 = (index+1). Gerçek index = r12 - 1
            dec.w   r12                         ; r12 = 0..3
            mov.w   r12, r13                    ; Basılan tuş -> r13

            ; Beklenen tuş ne? = ORDER[PROG]
            mov.w   #ORDER, r10
            add.w   &PROG, r10
            mov.b   0(r10), r14                 ; Beklenen index -> r14
            and.w   #0x00FF, r14

            cmp.w   r14, r13
            jne     SET_LOSE                    ; Yanlış tuş!

            ; DOĞRU TUŞ: Basılı olduğu sürece LED'i yak
            mov.w   r13, r11
            call    #IDX_TO_LED_MASK            ; r12 = LED Maskesi
            bis.b   r12, &P2OUT

            ; Tuş bırakılana kadar bekle
            mov.w   r13, r11
            call    #IDX_TO_BTN_MASK            ; r12 = Buton Maskesi
.WAIT_RELEASE:
            bit.b   r12, &P1IN                  ; Bırakıldı mı? (1 olur)
            jnz     .RELEASED
            jmp     .WAIT_RELEASE
.RELEASED:
            bic.b   #GAME_LEDS, &P2OUT

            ; FIX: Debounce için bırakıldıktan sonra çok kısa bekle
            mov.w   #50, r14
            call    #DELAY_MS

            ; Bir sonraki tuş için kesmeleri tekrar aç
            bic.b   #BTN_MASK, &P1IFG
            bis.b   #BTN_MASK, &P1IE

            ; İlerlemeyi artır
            inc.w   &PROG

            ; Seviye bitti mi kontrol et
            call    #GET_LEVEL_LENGTH           ; r12 = seviye uzunluğu
            cmp.w   r12, &PROG
            jeq     SET_LEVEL_WIN               ; Seviyeyi tamamladı!

            ; Olayı temizle ve devam et
            mov.w   #0, &BTN_EVENT
            jmp     PLAYER_LOOP

SET_LOSE:
            mov.w   #S_LEVEL_LOSE, &STATE
            jmp     PLAYER_DONE

SET_LEVEL_WIN:
            mov.w   #S_LEVEL_WIN, &STATE
            jmp     PLAYER_DONE

PLAYER_DONE:
            cmp.w   #S_LEVEL_WIN, &STATE
            jeq     LEVEL_WIN_HANDLER

            cmp.w   #S_LEVEL_LOSE, &STATE
            jeq     LEVEL_LOSE_HANDLER

            jmp     IDLE_STATE

;----------------------------
; SEVİYE KAZANILDI
;----------------------------
LEVEL_WIN_HANDLER:
            ; Dahili YEŞİL LED kısa yak
            bis.b   #GRN_LED, &P1OUT
            mov.w   #200, r14                   ; 200ms
            call    #DELAY_MS
            bic.b   #GRN_LED, &P1OUT

            ; Gereksinim: 2 saniye bekle
            call    #DELAY_2S

            ; Sonraki seviyeye geç
            inc.w   &LEVEL
            cmp.w   #NUM_LEVELS, &LEVEL
            jeq     GAME_WON                    ; Tüm seviyeler bitti mi?

            jmp     SHOW_LEVEL

;----------------------------
; KAYBETME DURUMU
;----------------------------
LEVEL_LOSE_HANDLER:
            bis.b   #RED_LED, &P1OUT            ; Kırmızı LED yanar

            ; Tüm LED'leri 2 saniye boyunca yak/söndür
            mov.w   #8, r15                     ; 8 kez toggle (Yaklaşık 2sn)
.BLINK_LOOP:
            xor.b   #GAME_LEDS, &P2OUT
            mov.w   #250, r14                   ; 250ms
            call    #DELAY_MS
            dec.w   r15
            jnz     .BLINK_LOOP

            bic.b   #GAME_LEDS, &P2OUT
            bic.b   #RED_LED, &P1OUT            ; Kırmızı LED söner

            ; IDLE moduna dön, WDT tohumlamayı tekrar başlat
            call    #RESUME_WDT_SEED
            jmp     IDLE_STATE

;----------------------------
; OYUN KAZANILDI
;----------------------------
GAME_WON:
            ; Gereksinim: WIN LED sürekli yanık kalmalı
            bis.b   #WIN_LED, &P2OUT

            call    #RESUME_WDT_SEED
            jmp     IDLE_STATE

;===============================================================================
; ALT PROGRAMLAR (Subroutines)
;===============================================================================

;----------------------------
; IDLE_CHECK_INPUTS
; Bekleme modunda butonları kontrol eder.
; - Tek butona uzun basılırsa: Zorluk seçilir ve oyun başlar.
; - 4 butona aynı anda uzun basılırsa: Easter Egg çalışır.
;----------------------------
IDLE_CHECK_INPUTS:
            push    r10
            push    r11
            push    r12
            push    r13

            ; Butonları oku
            mov.b   &P1IN, r12
            and.b   #BTN_MASK, r12

            ; Tümü basılı mı? (Hepsi 0 ise sonuç 0 olur)
            cmp.b   #0, r12
            jne     .NOT_ALL

            ; Easter Egg sayacı artır
            inc.w   &EGG_CNT
            cmp.w   #EGG_HOLD_T, &EGG_CNT
            jl      .DONE

            ; Easter Egg Başlat
            mov.w   #0, &EGG_CNT
            call    #EASTER_EGG
            jmp     .DONE

.NOT_ALL:
            mov.w   #0, &EGG_CNT

            ; Sadece bir butona mı basılıyor?
            mov.w   #0, r13                     ; Basılan sayısı
            mov.w   #0, r11                     ; Seçilen indeks

            ; BTN0 (P1.1) kontrol
            bit.b   #BIT1, r12
            jnz     .B1_NOT
            inc.w   r13
            mov.w   #0, r11
.B1_NOT:
            ; BTN1 (P1.2) kontrol
            bit.b   #BIT2, r12
            jnz     .B2_NOT
            inc.w   r13
            mov.w   #1, r11
.B2_NOT:
            ; BTN2 (P1.3) kontrol
            bit.b   #BIT3, r12
            jnz     .B3_NOT
            inc.w   r13
            mov.w   #2, r11
.B3_NOT:
            ; BTN3 (P1.4) kontrol
            bit.b   #BIT4, r12
            jnz     .B4_NOT
            inc.w   r13
            mov.w   #3, r11
.B4_NOT:

            ; Eğer tam olarak 1 buton basılı değilse sayacı sıfırla
            cmp.w   #1, r13
            jeq     .ONE_PRESSED

            mov.w   #0, &START_CNT
            jmp     .DONE

.ONE_PRESSED:
            inc.w   &START_CNT
            cmp.w   #START_HOLD_T, &START_CNT
            jl      .DONE

            ; Başlama şartı sağlandı!
            mov.w   r11, &DIFF                  ; Zorluk seviyesini kaydet
            mov.w   #0, &START_CNT

            ; Stack temizliği yapıp direkt atlamak yerine düzgün çıkış yap
            ; Ancak burada doğrudan jump yaparsak stack bozulabilir.
            ; IDLE döngüsünden çıkış için özel bayrak kullanmıyoruz, direkt jmp güvenli (RESET'ten sonra stack temiz)
            ; Sadece push'lananları geri almamız lazım.
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            jmp     START_GAME

.DONE:
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; RESUME_WDT_SEED
;----------------------------
RESUME_WDT_SEED:
            mov.w   #WDTPW|WDTTMSEL|WDTCNTCL|WDTIS1|WDTIS0, &WDTCTL
            bis.b   #WDTIE, &IE1
            ret

;----------------------------
; GET_LEVEL_LENGTH
; Çıkış: r12 = Seviye uzunluğu
;----------------------------
GET_LEVEL_LENGTH:
            push    r10
            mov.w   &LEVEL, r10
            rla.w   r10                         ; x2 (Word tablosu olduğu için)
            add.w   #LEVEL_LEN_TBL, r10
            mov.w   0(r10), r12
            pop     r10
            ret

;----------------------------
; SHOW_PATTERN
; Diziyi LED'lerde gösterir. Hız DIFF değişkenine bağlıdır.
;----------------------------
SHOW_PATTERN:
            push    r10
            push    r11
            push    r12
            push    r13
            push    r14

            call    #GET_LEVEL_LENGTH
            mov.w   r12, r13                    ; r13 = uzunluk

            mov.w   #0, r10                     ; i=0
.SHOW_LOOP:
            cmp.w   r13, r10
            jeq     .SHOW_DONE

            ; index = ORDER[i]
            mov.w   #ORDER, r11
            add.w   r10, r11
            mov.b   0(r11), r12
            and.w   #0x00FF, r12
            mov.w   r12, r11

            ; LED YAK
            call    #IDX_TO_LED_MASK
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            call    #DELAY_PATTERN_ON

            ; LED SÖNDÜR
            bic.b   #GAME_LEDS, &P2OUT
            call    #DELAY_PATTERN_OFF

            inc.w   r10
            jmp     .SHOW_LOOP

.SHOW_DONE:
            bic.b   #GAME_LEDS, &P2OUT
            pop     r14
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; ZAMANLAMA YARDIMCILARI
;----------------------------
DELAY_PATTERN_ON:
            push    r10
            mov.w   &DIFF, r10
            rla.w   r10
            add.w   #ON_TBL, r10
            mov.w   0(r10), r14
            call    #DELAY_MS
            pop     r10
            ret

DELAY_PATTERN_OFF:
            push    r10
            mov.w   &DIFF, r10
            rla.w   r10
            add.w   #OFF_TBL, r10
            mov.w   0(r10), r14
            call    #DELAY_MS
            pop     r10
            ret

DELAY_2S:
            mov.w   #2000, r14                  ; 2000ms = 2 Saniye
            call    #DELAY_MS
            ret

;----------------------------
; DELAY_MS
; Giriş: r14 = milisaniye (Yaklaşık)
; 1 MHz Clock varsayılmıştır.
;----------------------------
DELAY_MS:
            push    r15
.OUTER:
            mov.w   #250, r15                   ; 250 x 4 cycle = ~1000 cycle = 1ms
.INNER:
            dec.w   r15                         ; 1 cycle
            jnz     .INNER                      ; 2 cycle (Jump)
            dec.w   r14
            jnz     .OUTER
            pop     r15
            ret

;----------------------------
; DÖNÜŞÜM TABLOLARI (LUT)
;----------------------------
IDX_TO_LED_MASK:
            push    r10
            mov.w   #LED_LUT, r10
            add.w   r11, r10
            mov.b   0(r10), r12
            pop     r10
            ret

IDX_TO_BTN_MASK:
            push    r10
            mov.w   #BTN_LUT, r10
            add.w   r11, r10
            mov.b   0(r10), r12
            pop     r10
            ret

;----------------------------
; GEN_RANDOM_PATTERN
; Xorshift16 algoritması ile rastgele 0-3 arası sayılar üretir.
;----------------------------
GEN_RANDOM_PATTERN:
            push    r10
            push    r11
            push    r12
            push    r13
            push    r14
            push    r15

            mov.w   &SEED, r12
            mov.w   #ORDER, r10
            mov.w   #MAX_STEPS, r11

.RNG_LOOP:
            ; Xorshift algoritması
            mov.w   r12, r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13                         ; Shift right 7
            xor.w   r13, r12

            mov.w   r12, r13
            rla.w   r13                         ; Shift left 9 (9 kez rla)
            rla.w   r13
            rla.w   r13
            rla.w   r13
            rla.w   r13
            rla.w   r13
            rla.w   r13
            rla.w   r13
            rla.w   r13
            xor.w   r13, r12

            mov.w   r12, r13
            rra.w   r13                         ; Shift right 8
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            rra.w   r13
            xor.w   r13, r12

            ; Sonucun son 2 bitini al (0-3 arası sayı için)
            mov.w   r12, r15
            and.w   #3, r15
            mov.b   r15, 0(r10)
            inc.w   r10

            dec.w   r11
            jnz     .RNG_LOOP

            mov.w   r12, &SEED                  ; Tohumu güncelle
            pop     r15
            pop     r14
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; EASTER_EGG
; Sadece Oyun LED'leri ile özel animasyon, WIN LED korunur.
;----------------------------
EASTER_EGG:
            push    r12
            push    r13
            push    r14
            
            mov.b   &P2OUT, r12
            and.b   #WIN_LED, r12               ; Mevcut WIN durumunu sakla

            mov.w   #5, r14
.EG1:
            ; Desen 1
            mov.b   #(BIT0|BIT3), r13
            bis.b   r12, r13
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            push    r14
            mov.w   #100, r14
            call    #DELAY_MS
            pop     r14

            ; Desen 2
            mov.b   #(BIT1|BIT2), r13
            bis.b   r12, r13
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            push    r14
            mov.w   #100, r14
            call    #DELAY_MS
            pop     r14

            dec.w   r14
            jnz     .EG1

            ; Temizle ve çık
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            pop     r14
            pop     r13
            pop     r12
            ret

;===============================================================================
; KESME ALT PROGRAMLARI (ISR)
;===============================================================================

; Watchdog Timer ISR: Rastgelelik için sürekli sayar
wdt_ISR:
            inc.w   &SEED
            reti

; Port 1 ISR: Oyuncu tuşa bastığında tetiklenir
p1_ISR:
            push    r12

            ; Sadece PLAYER durumunda kabul et
            cmp.w   #S_PLAYER, &STATE
            jne     .CLR_EXIT

            ; Zaten işlenmeyi bekleyen bir olay varsa yoksay
            mov.w   &BTN_EVENT, r12
            cmp.w   #0, r12
            jne     .CLR_EXIT

            ; Yeni kesmeleri ana döngü işleyene kadar kapat (Debounce yardımı)
            bic.b   #BTN_MASK, &P1IE

            mov.b   &P1IFG, r12
            and.b   #BTN_MASK, r12

            bit.b   #BIT1, r12
            jz      .CHK2
            mov.w   #1, &BTN_EVENT
            jmp     .CLR_EXIT
.CHK2:
            bit.b   #BIT2, r12
            jz      .CHK3
            mov.w   #2, &BTN_EVENT
            jmp     .CLR_EXIT
.CHK3:
            bit.b   #BIT3, r12
            jz      .CHK4
            mov.w   #3, &BTN_EVENT
            jmp     .CLR_EXIT
.CHK4:
            bit.b   #BIT4, r12
            jz      .CLR_EXIT
            mov.w   #4, &BTN_EVENT

.CLR_EXIT:
            bic.b   #BTN_MASK, &P1IFG           ; Bayrakları temizle
            pop     r12
            reti

;===============================================================================
; VERİ VE TABLOLAR
;===============================================================================
            .data
            .align 2

STATE:      .word   0
LEVEL:      .word   0
PROG:       .word   0
DIFF:       .word   0
SEED:       .word   0x1234      ; Başlangıç tohumu

BTN_EVENT:  .word   0           ; 0=Yok, 1..4=Buton ID

START_CNT:  .word   0
EGG_CNT:    .word   0

ORDER:      .space  MAX_STEPS

            .sect ".const"
            .align 2

; Seviye Uzunlukları
LEVEL_LEN_TBL:
            .word   2, 3, 5

; Zorluk Zamanlamaları (ms cinsinden)
; Index: 0=Easy, 1=Med, 2=Hard, 3=Nightmare
ON_TBL:      .word  600, 450, 300, 150
OFF_TBL:     .word  300, 250, 150, 100

LED_LUT:     .byte  BIT0, BIT1, BIT2, BIT3
BTN_LUT:     .byte  BIT1, BIT2, BIT3, BIT4

;===============================================================================
; VEKTÖR TABLOSU (MSP430G2553 Standart)
;===============================================================================
            .sect   ".int10"                ; WDT Vector (FFF4h)
            .short  wdt_ISR
            
            .sect   ".int02"                ; Port1 Vector (FFE4h)
            .short  p1_ISR
            
            .sect   ".reset"                ; Reset Vector (FFFEh)
            .short  RESET
            .end
