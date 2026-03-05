# TaiDoc Interface Control Document (TICD) — Blood Glucose Meter

- **檔案名稱：** TICD-BGMeter
- **版本：** V1.6
- **更新日期：** 2013/09/27
- **來源：** TaiDoc Technology Co. (http://www.taidoc.com)

---

## 版本歷史

| # | 日期 | 作者 | 更新內容 | 版本 |
|---|------|------|---------|------|
| 1 | 2011/05/12 | Carol | 初版 | Ver1.0 |
| 2 | 2011/07/12 | Carol | 列出 TD-4222d 不支援的命令 | Ver1.1 |
| 3 | 2011/12/15 | Carol | 修改 | Ver1.2 |
| 4 | 2012/04/26 | Carol | 修改 | Ver1.3 |
| 5 | 2013/03/12 | Carol | Command 0x26 修改 | Ver1.4 |
| 6 | 2013/06/03 | Carol | Command 0x54 修改 | Ver1.5 |
| 7 | 2013/09/27 | Carol | Command 0x26 修改 | Ver1.6 |

---

## 1. 概述

本文件描述與血糖機通訊所使用的命令。在擷取裝置資料前，需先建立正確的連線通道（USB 或藍牙）。裝置為 Slave 端，等待來自 Host（電腦/閘道器）的請求。

### 縮寫定義

| 縮寫 | 說明 |
|------|------|
| **GW** | Gateway / Hub / 電腦端 |
| **MD** | Medical Device（血糖機、血壓計、體重計等） |
| **CMD** | Command（命令），1 byte |
| **ACK** | Acknowledgement（回應），1 byte |
| **NA** | Not Available |

---

## 2. 介面規格

### 通訊參數（RS232 串口）

| 參數 | 值 |
|------|-----|
| Baud Rate | 19200 |
| Data Bits | 8 |
| Parity | None |
| Start Bit | 1 |
| Stop Bit | 1 |

### 2.1 Frame 結構

每個 Frame 為 **8 bytes**，結構如下：

| Byte | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|------|------|------|--------|--------|--------|--------|------|----------|
| 名稱 | Start | CMD/ACK | Data_0 | Data_1 | Data_2 | Data_3 | Stop | CheckSum |

- **GW → MD（請求）：** Start = `0x51`，Stop = `0xA3`
- **MD → GW（回應）：** Start = `0x51`，Stop = `0xA5`
- **CheckSum：** Byte 1 ~ Byte 7 的加總，取低 8 位元

---

### 2.2 命令列表

| 命令名稱 | CMD/ACK | 方向 | 長度 | 備註 |
|---------|---------|------|------|------|
| 讀取裝置時鐘 | 0x23 | GW↔MD | 8 | |
| 讀取裝置型號 | 0x24 | GW↔MD | 8 | TD-4222d 不支援 |
| 讀取儲存資料 Part 1（時間） | 0x25 | GW↔MD | 8 | |
| 讀取儲存資料 Part 2（結果） | 0x26 | GW↔MD | 8 | |
| 讀取裝置序號 Part 1 | 0x27 | GW↔MD | 8 | |
| 讀取裝置序號 Part 2 | 0x28 | GW↔MD | 8 | |
| 讀取儲存資料筆數 | 0x2B | GW↔MD | 8 | |
| 寫入系統時鐘 | 0x33 | GW↔MD | 8 | |
| 關閉裝置 | 0x50 | GW↔MD | 8 | |
| 清除所有記憶體 | 0x52 | GW↔MD | 8 | |
| 進入通訊模式通知 | 0x54 | MD→GW | 8 | TD-4222d 不支援 |

---

### 2.2.1 [0x23] 讀取裝置時鐘（4 bytes）

讀取裝置的日期與時間（精確到分鐘）。

**請求：**

| Byte | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|------|------|------|------|------|------|------|------|----------|
| | 0x51 | 0x23 | 0x00 | 0x00 | 0x00 | 0x00 | 0xA3 | CheckSum |

**回應：**

| Byte | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|------|------|------|--------|--------|--------|------|------|----------|
| | 0x51 | 0x23 | Data_0 | Data_1 | Data_2 | Data_3 | 0xA5 | CheckSum |

**日期編碼（Data_1 + Data_0，16-bit word）：**

```
MSB                                          LSB
Data_1                    Data_0
[Year (7-bit)][Month (4-bit)][Day (5-bit)]
```

- Year：7-bit（0~127，相對於 2000 年）
- Month：4-bit（1~12）
- Day：5-bit（1~31）

**時間編碼（Data_3 = Hour, Data_2 = Minute）：**

```
Data_3: [NA (3-bit)][Hour (5-bit)]
Data_2: [NA (2-bit)][Minute (6-bit)]
```

---

### 2.2.2 [0x24] 讀取裝置型號

> **注意：TD-4222d 不支援此命令**

**請求：** CMD = 0x24，Data_0~3 = 0x00

**回應：**
- Data_1 + Data_0：裝置型號（4 位數字，Data_1 為高位元組）
- Data_2, Data_3：未定義

---

### 2.2.3 [0x25] 讀取儲存資料 Part 1（量測時間）

根據 Index 讀取指定筆的量測日期時間。

**請求：**
- CMD = 0x25
- Data_0 + Data_1：Index（0x0000 = 最新一筆）
- Data_2, Data_3 = 0x00

**回應：**
- Data_0 + Data_1：量測日期（編碼同 0x23 的 Table A）
- Data_2：量測分鐘（編碼同 0x23 的 Table B）

---

### 2.2.4 [0x26] 讀取儲存資料 Part 2（量測結果）

根據 Index 讀取指定筆的血糖值。

**請求：**
- CMD = 0x26
- Data_0 + Data_1：Index（0x0000 = 最新一筆）
- Data_2, Data_3 = 0x00

**回應：**
- Data_0 + Data_1（Glucose）：血糖值（16-bit），單位 mg/dL
  - 換算：mg/dL = mmol/L × 18
- Data_2 + Data_3（Param）：參數

**Param 位元欄位（Data_3 + Data_2）：**

```
MSB                                              LSB
Data_3                         Data_2
[GlucoseType (2-bit)][NA (2-bit)][Code (4-bit)][NA (8-bit)]
```

**Glucose Type：**

| 值 | 含義 |
|----|------|
| 0x0 | Gen（一般） |
| 0x1 | AC（飯前） |
| 0x2 | PC（飯後） |
| 0x3 | QC（品質控制） |

---

### 2.2.5 [0x27] 讀取裝置序號 Part 1

序號由 16 個字元組成（0~9, A~F），分兩次讀取。

**請求：** CMD = 0x27，Data_0~3 = 0x00

**回應：** Data_0~3 = SN_0 ~ SN_3

範例序號：`32502102 4013102A`
- 前 4 bytes 來自 0x28（SN_4~SN_7）
- 後 4 bytes 來自 0x27（SN_0~SN_3）

---

### 2.2.6 [0x28] 讀取裝置序號 Part 2

**請求：** CMD = 0x28，Data_0~3 = 0x00

**回應：** Data_0~3 = SN_4 ~ SN_7

完整序號 = 0x28 回應 + 0x27 回應 = SN_7 SN_6 SN_5 SN_4 SN_3 SN_2 SN_1 SN_0

---

### 2.2.7 [0x2B] 讀取儲存資料筆數

**請求：** CMD = 0x2B，Data_0~3 = 0x00

**回應：**
- Data_0 + Data_1：儲存筆數（16-bit word）
- Data_2, Data_3 = 0x00

---

### 2.2.8 [0x33] 寫入系統時鐘（4 bytes）

將日期時間寫入裝置。格式與 0x23 相同。

**請求：**
- CMD = 0x33
- Data_0 + Data_1：Day + Month + Year（編碼同 0x23）
- Data_2：Minute
- Data_3：Hour

**回應：** 回傳相同的日期時間資料表示寫入成功。

---

### 2.2.9 [0x50] 關閉裝置

從 GW 端關閉裝置電源。

**請求：** CMD = 0x50，Data_0~3 = 0x00

**回應：** CMD = 0x50，Data_0~3 = 0x00（確認關閉）

---

### 2.2.10 [0x52] 清除/刪除所有記憶體

刪除裝置中所有的量測資料。

**請求：** CMD = 0x52，Data_0~3 = 0x00

**回應：** CMD = 0x52，Data_0~3 = 0x00（確認清除）

---

### 2.2.11 [0x54] 進入通訊模式通知

> **注意：TD-4222d 不支援此命令**

部分型號的裝置在連線建立後（如 RS-232），會主動發送 0x54 命令通知 Host 端裝置已進入通訊模式、準備好接收命令。

**方向：** MD → GW（裝置主動發送）

**資料：** CMD = 0x54，Data_0~3 = 0x00

**Host 處理：** 不需要回應。但 Host 需在接收佇列中處理此通知，避免與預期的命令回應混淆。

---

## 附錄：Frame 範例

### 讀取裝置時鐘的請求

```
Byte:     1     2     3     4     5     6     7     8
Value:  0x51  0x23  0x00  0x00  0x00  0x00  0xA3  0x11
                                                   ↑
                                          CheckSum = (0x51+0x23+0x00+0x00+0x00+0x00+0xA3) & 0xFF
```

### 日期解碼範例

假設 Data_1 = 0x1A, Data_0 = 0x45：

```
16-bit word = 0x1A45 = 0001 1010 0100 0101
Year  (bit 15-9): 0001101 = 13 → 2013 年
Month (bit 8-5):  0010   = 2  → 2 月
Day   (bit 4-0):  00101  = 5  → 5 日
```
