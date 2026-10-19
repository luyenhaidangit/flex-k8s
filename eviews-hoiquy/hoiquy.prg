' Hoi quy Y = b1 + b2*X + b3*Z + u  (n = 10)
wfcreate(wf=hoiquy, page=data) u 1 10

series y
series x
series z
y.fill 40, 44, 46, 48, 52, 58, 60, 68, 74, 90
x.fill 8, 9, 9, 10, 11, 12, 12, 13, 14, 15
z.fill 5, 5, 4.5, 4.5, 4, 4, 3.5, 3.5, 3, 2.5

' a) Uoc luong ham hoi quy mau
equation eq1.ls y c x z
show eq1

' Khoang tin cay 95% cua he so
show eq1.cinterval(0.95)

' Da cong tuyen: tuong quan X, Z
group g x z
show g.cor

' Kiem dinh tu tuong quan (Breusch-Godfrey) va phuong sai sai so thay doi (White)
freeze(bg) eq1.auto(1)
freeze(wh) eq1.white

' Du bao tai X0 = 15, Z0 = 6: them 1 quan sat
pagestruct(end=11)
x(11) = 15
z(11) = 6
smpl 11 11
eq1.forecast(f=na) yf yf_se
smpl @all
show yf yf_se
' Khoang tin cay: yf +/- @qtdist(0.975, 7) * yf_se
' (yf_se la sai so chuan du bao CA BIET, dung cho khoang du bao Y0)
